# Builds MixBar.driver (Core Audio HAL AudioServerPlugIn) with Command Line
# Tools only. No Xcode required.

BUILD      := ../build
BUNDLE     := $(BUILD)/MixBar.driver
EXE        := $(BUNDLE)/Contents/MacOS/MixBarDriver
ARCHS      := -arch arm64 -arch x86_64
MIN        := -mmacosx-version-min=11.0

CXX        := clang++
OBJC       := clang

INCLUDES   := -I. -IDeviceClients -IPublicUtility -I../shared
DEFINES    := -DNDEBUG -DCoreAudio_UseSysLog=1
WARN       := -Wall -Wno-deprecated-declarations -Wno-unused-parameter
CXXFLAGS   := -std=gnu++14 -O2 -fPIC $(ARCHS) $(MIN) $(INCLUDES) $(DEFINES) $(WARN)
OBJCFLAGS  := -std=gnu11 -O2 -fPIC -fobjc-arc $(ARCHS) $(MIN) $(INCLUDES) $(DEFINES) $(WARN)
LDFLAGS    := -bundle $(ARCHS) $(MIN) \
              -framework CoreAudio -framework CoreFoundation \
              -framework Foundation -framework Accelerate

CPP_SRCS   := $(wildcard BGM_*.cpp) \
              $(wildcard DeviceClients/*.cpp) \
              ../shared/BGM_Utils.cpp \
              PublicUtility/CACFArray.cpp \
              PublicUtility/CACFDictionary.cpp \
              PublicUtility/CACFNumber.cpp \
              PublicUtility/CACFString.cpp \
              PublicUtility/CADebugMacros.cpp \
              PublicUtility/CADebugPrintf.cpp \
              PublicUtility/CADebugger.cpp \
              PublicUtility/CADispatchQueue.cpp \
              PublicUtility/CAHostTimeBase.cpp \
              PublicUtility/CAMutex.cpp \
              PublicUtility/CAPThread.cpp \
              PublicUtility/CARingBuffer.cpp \
              PublicUtility/CAVolumeCurve.cpp
M_SRCS     := BGM_XPCHelper.m
C_SRCS     := PublicUtility/BGMDebugLogging.c

OBJDIR     := $(BUILD)/driver-obj
CPP_OBJS   := $(patsubst %.cpp,$(OBJDIR)/%.o,$(CPP_SRCS))
M_OBJS     := $(patsubst %.m,$(OBJDIR)/%.o,$(M_SRCS))
C_OBJS     := $(patsubst %.c,$(OBJDIR)/%.o,$(C_SRCS))
OBJS       := $(CPP_OBJS) $(M_OBJS) $(C_OBJS)

all: $(BUNDLE)

$(OBJDIR)/%.o: %.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJDIR)/%.o: %.m
	@mkdir -p $(dir $@)
	$(OBJC) $(OBJCFLAGS) -c $< -o $@

$(OBJDIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(OBJC) $(OBJCFLAGS) -c $< -o $@

$(EXE): $(OBJS)
	@mkdir -p $(dir $@)
	$(CXX) $(LDFLAGS) $(OBJS) -o $@

$(BUNDLE): $(EXE) Info.plist DeviceIcon.icns
	@mkdir -p $(BUNDLE)/Contents/Resources
	cp Info.plist $(BUNDLE)/Contents/
	cp DeviceIcon.icns $(BUNDLE)/Contents/Resources/
	codesign --force --sign - $(BUNDLE)
	@echo "Built $(BUNDLE)"

clean:
	rm -rf $(OBJDIR) $(BUNDLE)

.PHONY: all clean
