ARCHS = arm64 arm64e
TARGET = iphone:clang:15.6:15.0
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VPNTriggerManager
VPNTriggerManager_FILES = Tweak.m
VPNTriggerManager_CFLAGS = -fobjc-arc
VPNTriggerManager_FRAMEWORKS = Foundation CallKit NetworkExtension

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += VPNTriggerManagerPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

