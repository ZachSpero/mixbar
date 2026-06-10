// MixBarEngine.h
// MixBar
//
// ObjC facade over the audio engine (virtual device + playthrough + per-app
// volumes) so the SwiftUI app never touches C++ directly.
//
// This file is part of MixBar, derived from Background Music.
// GPLv2. See LICENSE.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One entry from the driver's app-volumes list.
@interface MXBAppVolume : NSObject
@property (nonatomic) pid_t pid;
@property (nonatomic, copy, nullable) NSString *bundleID;
/// 0 to 100. 50 is unity gain (no change).
@property (nonatomic) NSInteger relativeVolume;
/// -100 (left) to 100 (right). 0 is centered.
@property (nonatomic) NSInteger panPosition;
@end

/// An output device MixBar can play through.
@interface MXBOutputDevice : NSObject
@property (nonatomic) UInt32 audioObjectID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *uid;
@end

extern NSString *const MixBarEngineErrorDomain;

@interface MixBarEngine : NSObject

/// Finds the MixBar virtual device, picks an output device (the current
/// system default, or the first usable real device if MixBar is already the
/// default), starts playthrough, and sets MixBar as the system default
/// output device. Returns nil and sets error if the driver isn't installed.
+ (nullable MixBarEngine *)startEngineWithPreferredOutputUID:(nullable NSString *)preferredUID
                                                       error:(NSError **)error;

/// Connects to the driver without starting playthrough or changing the
/// default device. Volume getters/setters work; playthrough does not run.
/// Used by mixbarctl so it can adjust volumes while the app is running.
+ (nullable MixBarEngine *)inspectorWithError:(NSError **)error;

- (instancetype)init NS_UNAVAILABLE;

/// Stops playthrough and restores the real output device as the system
/// default. Call before the app quits.
- (void)stopAndRestoreDefaultDevice;

/// Sets MixBar as the default output device again if something else took it
/// back (for example a quitting older instance restoring its device).
- (void)reassertDefaultDevice;

/// All devices that can currently be used as the real output device.
- (NSArray<MXBOutputDevice *> *)outputDevices;

/// The device playthrough is currently sending audio to.
@property (nonatomic, readonly) UInt32 outputDeviceID;
@property (nonatomic, readonly, copy) NSString *outputDeviceUID;

/// Switch playthrough to another output device.
- (BOOL)setOutputDeviceByID:(UInt32)deviceID error:(NSError **)error;

/// Set an app's volume. 0 to 100, 50 is unity. Identify the app by pid,
/// bundle ID, or both (pass -1 / nil to omit one).
- (BOOL)setVolume:(NSInteger)volume
           forPID:(pid_t)pid
         bundleID:(nullable NSString *)bundleID;

/// Set an app's stereo pan. -100 (left) to 100 (right).
- (BOOL)setPan:(NSInteger)pan
        forPID:(pid_t)pid
      bundleID:(nullable NSString *)bundleID;

/// The driver's current per-app volume list.
- (NSArray<MXBAppVolume *> *)appVolumes;

/// True if any client app is currently playing audio through MixBar.
@property (nonatomic, readonly) BOOL deviceIsRunningSomewhere;

/// True if the given device currently has IO running. When MixBar is the
/// default device and audio is playing, the real output device should be
/// running because playthrough is pumping audio into it.
+ (BOOL)deviceIsRunning:(UInt32)deviceID;

@end

NS_ASSUME_NONNULL_END
