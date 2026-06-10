// MixBarEngine.mm
// MixBar
//
// This file is part of MixBar, derived from Background Music.
// GPLv2. See LICENSE.

#import "MixBarEngine.h"

#include "BGM_Types.h"
#include "BGM_Utils.h"
#include "BGMAudioDevice.h"
#include "BGMBackgroundMusicDevice.h"
#include "BGMDeviceControlSync.h"
#include "BGMPlayThrough.h"

#include "CACFArray.h"
#include "CACFDictionary.h"
#include "CACFString.h"
#include "CAException.h"
#include "CAHALAudioSystemObject.h"
#include "CAPropertyAddress.h"

#include <vector>

NSString *const MixBarEngineErrorDomain = @"com.zachspero.mixbar.engine";

static OSStatus MXBDeviceListenerProc(AudioObjectID inObjectID,
                                      UInt32 inNumberAddresses,
                                      const AudioObjectPropertyAddress *inAddresses,
                                      void *inClientData);

@implementation MXBAppVolume
@end

@implementation MXBOutputDevice
@end

@interface MixBarEngine ()
- (void)handleDeviceNotification:(AudioObjectID)deviceID
                    numAddresses:(UInt32)numAddresses
                       addresses:(const AudioObjectPropertyAddress *)addresses;
@end

@implementation MixBarEngine {
    BGMBackgroundMusicDevice *mixbarDevice;   // owned
    BGMAudioDevice outputDevice;
    BGMDeviceControlSync deviceControlSync;
    BGMPlayThrough playThrough;
    BGMPlayThrough playThroughUISounds;
    BOOL listenersRegistered;
    BOOL playThroughActive;
    NSRecursiveLock *stateLock;
}

+ (nullable MixBarEngine *)startEngineWithPreferredOutputUID:(nullable NSString *)preferredUID
                                                       error:(NSError **)error {
    return [[MixBarEngine alloc] initAndStartWithPreferredOutputUID:preferredUID error:error];
}

+ (nullable MixBarEngine *)inspectorWithError:(NSError **)error {
    return [[MixBarEngine alloc] initForInspection:error];
}

- (nullable instancetype)initForInspection:(NSError **)error {
    if (!(self = [super init])) {
        return nil;
    }

    stateLock = [NSRecursiveLock new];
    listenersRegistered = NO;
    playThroughActive = NO;
    outputDevice = BGMAudioDevice(kAudioObjectUnknown);

    try {
        mixbarDevice = new BGMBackgroundMusicDevice;
    } catch (const CAException &e) {
        if (error) {
            *error = [NSError errorWithDomain:MixBarEngineErrorDomain
                                         code:e.GetError()
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"MixBar virtual device not found. Is the driver installed?"}];
        }
        return nil;
    }

    return self;
}

#pragma mark Lifecycle

- (nullable instancetype)initAndStartWithPreferredOutputUID:(nullable NSString *)preferredUID
                                                       error:(NSError **)error {
    if (!(self = [super init])) {
        return nil;
    }

    stateLock = [NSRecursiveLock new];
    listenersRegistered = NO;
    playThroughActive = NO;
    outputDevice = BGMAudioDevice(kAudioObjectUnknown);

    try {
        mixbarDevice = new BGMBackgroundMusicDevice;
    } catch (const CAException &e) {
        if (error) {
            *error = [NSError errorWithDomain:MixBarEngineErrorDomain
                                         code:e.GetError()
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"MixBar virtual device not found. Is the driver installed?"}];
        }
        return nil;
    }

    AudioObjectID initialOutputID = [self pickInitialOutputDeviceWithPreferredUID:preferredUID];
    if (initialOutputID == kAudioObjectUnknown) {
        if (error) {
            *error = [NSError errorWithDomain:MixBarEngineErrorDomain
                                         code:1 /* output device not found */
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"No usable output device found."}];
        }
        delete mixbarDevice;
        mixbarDevice = nullptr;
        return nil;
    }

    NSError *setErr = nil;
    if (![self setOutputDeviceByID:initialOutputID error:&setErr]) {
        if (error) {
            *error = setErr;
        }
        delete mixbarDevice;
        mixbarDevice = nullptr;
        return nil;
    }

    [self registerListeners];

    try {
        mixbarDevice->SetAsOSDefault();
    } catch (const CAException &e) {
        if (error) {
            *error = [NSError errorWithDomain:MixBarEngineErrorDomain
                                         code:e.GetError()
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"Couldn't set MixBar as the default output device."}];
        }
        [self removeListeners];
        delete mixbarDevice;
        mixbarDevice = nullptr;
        return nil;
    }

    return self;
}

- (void)stopAndRestoreDefaultDevice {
    // Copy state under the lock, then call the HAL with the lock RELEASED.
    // The HAL can block our requests until our property listener callbacks
    // return, and those callbacks take stateLock, so holding it across a
    // HAL call deadlocks the whole app. (Same pattern as BGMApp.)
    BGMBackgroundMusicDevice *deviceCopy;
    AudioObjectID outputDeviceID;
    BOOL wasActive;

    [stateLock lock];
    deviceCopy = mixbarDevice;
    outputDeviceID = outputDevice.GetObjectID();
    wasActive = playThroughActive;
    playThroughActive = NO;
    [stateLock unlock];

    if (!deviceCopy || !wasActive) {
        return;
    }

    [self removeListeners];

    try {
        deviceCopy->UnsetAsOSDefault(outputDeviceID);
    } catch (const CAException &e) {
        NSLog(@"MixBarEngine: failed to restore default device (%d)", (int)e.GetError());
    }

    try {
        playThrough.Deactivate();
        playThroughUISounds.Deactivate();
        deviceControlSync.Deactivate();
    } catch (const CAException &e) {
        NSLog(@"MixBarEngine: error deactivating playthrough (%d)", (int)e.GetError());
    }
}

- (void)reassertDefaultDevice {
    // Copy state under the lock; call the HAL with the lock released.
    // See stopAndRestoreDefaultDevice for why holding stateLock across a
    // HAL call deadlocks.
    BGMBackgroundMusicDevice *deviceCopy;
    BOOL active;

    [stateLock lock];
    deviceCopy = mixbarDevice;
    active = playThroughActive;
    [stateLock unlock];

    if (!deviceCopy || !active) {
        return;
    }

    try {
        deviceCopy->SetAsOSDefault();
    } catch (const CAException &e) {
        NSLog(@"MixBarEngine: failed to reassert default device (%d)", (int)e.GetError());
    }
}

#pragma mark Output devices

// The current system default, unless that's one of our virtual devices (e.g.
// after a crash), in which case the first real device that can be an output.
- (AudioObjectID)pickInitialOutputDeviceWithPreferredUID:(nullable NSString *)preferredUID {
    try {
        if (preferredUID) {
            for (MXBOutputDevice *d in [self outputDevices]) {
                if ([d.uid isEqualToString:preferredUID]) {
                    return d.audioObjectID;
                }
            }
        }

        CAHALAudioSystemObject audioSystem;
        BGMAudioDevice defaultDevice(audioSystem.GetDefaultAudioDevice(false, false));

        if (![self isOwnVirtualDevice:defaultDevice] && defaultDevice.CanBeOutputDeviceInBGMApp()) {
            return defaultDevice.GetObjectID();
        }

        NSArray<MXBOutputDevice *> *devices = [self outputDevices];
        if (devices.count > 0) {
            return devices[0].audioObjectID;
        }
    } catch (const CAException &e) {
        NSLog(@"MixBarEngine: error picking initial output device (%d)", (int)e.GetError());
    }

    return kAudioObjectUnknown;
}

- (BOOL)isOwnVirtualDevice:(BGMAudioDevice &)device {
    try {
        CACFString uid(device.CopyDeviceUID());
        NSString *uidStr = (__bridge NSString *)uid.GetCFString();
        return [uidStr isEqualToString:@kBGMDeviceUID] ||
               [uidStr isEqualToString:@kBGMDeviceUID_UISounds] ||
               [uidStr isEqualToString:@kBGMNullDeviceUID];
    } catch (const CAException &e) {
        return NO;
    }
}

- (NSArray<MXBOutputDevice *> *)outputDevices {
    NSMutableArray<MXBOutputDevice *> *result = [NSMutableArray new];

    try {
        CAHALAudioSystemObject audioSystem;
        UInt32 numDevices = audioSystem.GetNumberAudioDevices();
        std::vector<AudioObjectID> deviceIDs(numDevices);
        audioSystem.GetAudioDevices(numDevices, deviceIDs.data());

        for (UInt32 i = 0; i < numDevices; i++) {
            BGMAudioDevice device(deviceIDs[i]);

            try {
                if ([self isOwnVirtualDevice:device] || !device.CanBeOutputDeviceInBGMApp()) {
                    continue;
                }

                MXBOutputDevice *d = [MXBOutputDevice new];
                d.audioObjectID = deviceIDs[i];

                CACFString uid(device.CopyDeviceUID());
                d.uid = (__bridge NSString *)uid.GetCFString() ?: @"";

                CFStringRef nameRef = device.CopyName();
                if (nameRef) {
                    d.name = (__bridge_transfer NSString *)nameRef;
                } else {
                    d.name = d.uid;
                }

                [result addObject:d];
            } catch (const CAException &e) {
                // Skip devices that error when queried.
                continue;
            }
        }
    } catch (const CAException &e) {
        NSLog(@"MixBarEngine: error listing output devices (%d)", (int)e.GetError());
    }

    return result;
}

- (UInt32)outputDeviceID {
    [stateLock lock];
    @try {
        return outputDevice.GetObjectID();
    } @finally {
        [stateLock unlock];
    }
}

- (NSString *)outputDeviceUID {
    [stateLock lock];
    @try {
        try {
            CACFString uid(outputDevice.CopyDeviceUID());
            return (__bridge NSString *)uid.GetCFString() ?: @"";
        } catch (const CAException &e) {
            return @"";
        }
    } @finally {
        [stateLock unlock];
    }
}

- (BOOL)setOutputDeviceByID:(UInt32)deviceID error:(NSError **)error {
    [stateLock lock];
    @try {
        try {
            BGMAudioDevice newOutputDevice(deviceID);

            // Deactivate playthrough rather than stopping it so it can't be
            // started by HAL notifications while we update control sync.
            playThrough.Deactivate();
            playThroughUISounds.Deactivate();

            deviceControlSync.SetDevices(*mixbarDevice, newOutputDevice);
            deviceControlSync.Activate();

            playThrough.SetDevices(mixbarDevice, &newOutputDevice);
            playThrough.Activate();

            BGMAudioDevice uiSoundsDevice = mixbarDevice->GetUISoundsBGMDeviceInstance();
            playThroughUISounds.SetDevices(&uiSoundsDevice, &newOutputDevice);
            playThroughUISounds.Activate();

            outputDevice = newOutputDevice;

            // Audio might be playing already, so start playthrough, then stop
            // it again if nothing is actually playing (it burns CPU).
            playThrough.Start();
            playThroughUISounds.Start();
            playThrough.StopIfIdle();
            playThroughUISounds.StopIfIdle();

            playThroughActive = YES;
            return YES;
        } catch (const CAException &e) {
            if (error) {
                *error = [NSError errorWithDomain:MixBarEngineErrorDomain
                                             code:e.GetError()
                                         userInfo:@{NSLocalizedDescriptionKey:
                    @"Couldn't switch to that output device."}];
            }
            return NO;
        }
    } @finally {
        [stateLock unlock];
    }
}

#pragma mark App volumes

- (BOOL)setVolume:(NSInteger)volume
           forPID:(pid_t)pid
         bundleID:(nullable NSString *)bundleID {
    NSInteger clamped = MAX((NSInteger)kAppRelativeVolumeMinRawValue,
                            MIN((NSInteger)kAppRelativeVolumeMaxRawValue, volume));
    try {
        // SetAppVolume takes ownership of the bundle ID string (it wraps it
        // in a releasing CACFString), so pass a +1 reference.
        CFStringRef bid = bundleID ? (__bridge_retained CFStringRef)[bundleID copy] : NULL;
        mixbarDevice->SetAppVolume((SInt32)clamped, pid, bid);
        return YES;
    } catch (const CAException &e) {
        NSLog(@"MixBarEngine: failed to set volume (%d)", (int)e.GetError());
        return NO;
    }
}

- (BOOL)setPan:(NSInteger)pan
        forPID:(pid_t)pid
      bundleID:(nullable NSString *)bundleID {
    NSInteger clamped = MAX((NSInteger)kAppPanLeftRawValue,
                            MIN((NSInteger)kAppPanRightRawValue, pan));
    try {
        // See setVolume: SetAppPanPosition takes ownership of the string.
        CFStringRef bid = bundleID ? (__bridge_retained CFStringRef)[bundleID copy] : NULL;
        mixbarDevice->SetAppPanPosition((SInt32)clamped, pid, bid);
        return YES;
    } catch (const CAException &e) {
        NSLog(@"MixBarEngine: failed to set pan (%d)", (int)e.GetError());
        return NO;
    }
}

- (NSArray<MXBAppVolume *> *)appVolumes {
    NSMutableArray<MXBAppVolume *> *result = [NSMutableArray new];

    try {
        CACFArray volumes(mixbarDevice->GetAppVolumes(), true);

        for (UInt32 i = 0; i < volumes.GetNumberItems(); i++) {
            CFDictionaryRef dictRef = NULL;
            if (!volumes.GetDictionary(i, dictRef) || !dictRef) {
                continue;
            }
            CACFDictionary dict(dictRef, false);

            MXBAppVolume *v = [MXBAppVolume new];

            SInt32 pid = -1;
            if (dict.GetSInt32(CFSTR(kBGMAppVolumesKey_ProcessID), pid)) {
                v.pid = pid;
            } else {
                v.pid = -1;
            }

            CFStringRef bid = NULL;
            if (dict.GetString(CFSTR(kBGMAppVolumesKey_BundleID), bid) && bid) {
                v.bundleID = (__bridge NSString *)bid;
            }

            SInt32 rvol = kAppRelativeVolumeMaxRawValue / 2;
            dict.GetSInt32(CFSTR(kBGMAppVolumesKey_RelativeVolume), rvol);
            v.relativeVolume = rvol;

            SInt32 ppos = kAppPanCenterRawValue;
            dict.GetSInt32(CFSTR(kBGMAppVolumesKey_PanPosition), ppos);
            v.panPosition = ppos;

            [result addObject:v];
        }
    } catch (const CAException &e) {
        NSLog(@"MixBarEngine: failed to read app volumes (%d)", (int)e.GetError());
    }

    return result;
}

#pragma mark Playthrough start/stop notifications

+ (BOOL)deviceIsRunning:(UInt32)deviceID {
    try {
        BGMAudioDevice device(deviceID);
        return device.IsRunningSomewhere();
    } catch (const CAException &e) {
        return NO;
    }
}

- (BOOL)deviceIsRunningSomewhere {
    try {
        return mixbarDevice->IsRunningSomewhere();
    } catch (const CAException &e) {
        return NO;
    }
}

- (void)registerListeners {
    if (listenersRegistered || !mixbarDevice) {
        return;
    }

    void *bridgeSelf = (__bridge void *)self;

    auto addListeners = [&](AudioObjectID deviceID) {
        try {
            BGMAudioDevice device(deviceID);
            device.AddPropertyListener(
                CAPropertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere),
                &MXBDeviceListenerProc, bridgeSelf);
            device.AddPropertyListener(
                kBGMRunningSomewhereOtherThanBGMAppAddress,
                &MXBDeviceListenerProc, bridgeSelf);
        } catch (const CAException &e) {
            NSLog(@"MixBarEngine: failed to register listeners (%d)", (int)e.GetError());
        }
    };

    addListeners(mixbarDevice->GetObjectID());
    addListeners(mixbarDevice->GetUISoundsBGMDeviceInstance().GetObjectID());

    listenersRegistered = YES;
}

- (void)removeListeners {
    if (!listenersRegistered || !mixbarDevice) {
        return;
    }

    void *bridgeSelf = (__bridge void *)self;

    auto removeFrom = [&](AudioObjectID deviceID) {
        try {
            BGMAudioDevice device(deviceID);
            device.RemovePropertyListener(
                CAPropertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere),
                &MXBDeviceListenerProc, bridgeSelf);
            device.RemovePropertyListener(
                kBGMRunningSomewhereOtherThanBGMAppAddress,
                &MXBDeviceListenerProc, bridgeSelf);
        } catch (const CAException &e) {
            NSLog(@"MixBarEngine: failed to remove listeners (%d)", (int)e.GetError());
        }
    };

    removeFrom(mixbarDevice->GetObjectID());
    removeFrom(mixbarDevice->GetUISoundsBGMDeviceInstance().GetObjectID());

    listenersRegistered = NO;
}

- (void)handleDeviceNotification:(AudioObjectID)deviceID
                    numAddresses:(UInt32)numAddresses
                       addresses:(const AudioObjectPropertyAddress *)addresses {
    for (UInt32 i = 0; i < numAddresses; i++) {
        AudioObjectID notifiedDeviceID = deviceID;
        switch (addresses[i].mSelector) {
            case kAudioDevicePropertyDeviceIsRunningSomewhere: {
                // Start playthrough when a client starts IO on the device.
                // Only start when the property actually reads true; starting
                // unconditionally loops, because our own playthrough stopping
                // and starting also fires this notification.
                dispatch_async(BGMGetDispatchQueue_PriorityUserInteractive(), ^{
                    [self startPlayThroughIfDeviceRunning:notifiedDeviceID];
                });
                break;
            }
            case kAudioDeviceCustomPropertyDeviceIsRunningSomewhereOtherThanBGMApp: {
                // The driver fires this after other clients have been idle
                // for a couple of seconds. StopIfIdle re-checks the property
                // itself, so it's safe to call either way.
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self stopPlayThroughIfIdle:notifiedDeviceID];
                });
                break;
            }
            default:
                break;
        }
    }
}

- (BGMPlayThrough &)playThroughForDevice:(AudioObjectID)deviceID {
    return (deviceID == mixbarDevice->GetUISoundsBGMDeviceInstance().GetObjectID())
        ? playThroughUISounds
        : playThrough;
}

- (void)startPlayThroughIfDeviceRunning:(AudioObjectID)deviceID {
    [stateLock lock];
    @try {
        if (!mixbarDevice || outputDevice.GetObjectID() == kAudioObjectUnknown) {
            return;
        }

        bool isRunningSomewhere = true;
        try {
            isRunningSomewhere = (BGMAudioDevice(deviceID).GetPropertyData_UInt32(
                CAPropertyAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)) != 0);
        } catch (const CAException &e) {
            // Try to start anyway if we can't read the property.
        }

        if (isRunningSomewhere) {
            try {
                [self playThroughForDevice:deviceID].Start();
            } catch (const CAException &e) {
                NSLog(@"MixBarEngine: playthrough start error (%d)", (int)e.GetError());
            }
        }
    } @finally {
        [stateLock unlock];
    }
}

- (void)stopPlayThroughIfIdle:(AudioObjectID)deviceID {
    [stateLock lock];
    @try {
        if (!mixbarDevice || outputDevice.GetObjectID() == kAudioObjectUnknown) {
            return;
        }
        try {
            [self playThroughForDevice:deviceID].StopIfIdle();
        } catch (const CAException &e) {
            NSLog(@"MixBarEngine: playthrough stop error (%d)", (int)e.GetError());
        }
    } @finally {
        [stateLock unlock];
    }
}

@end

static OSStatus MXBDeviceListenerProc(AudioObjectID inObjectID,
                                      UInt32 inNumberAddresses,
                                      const AudioObjectPropertyAddress *inAddresses,
                                      void *inClientData) {
    MixBarEngine *engine = (__bridge MixBarEngine *)inClientData;
    [engine handleDeviceNotification:inObjectID
                        numAddresses:inNumberAddresses
                           addresses:inAddresses];
    return noErr;
}
