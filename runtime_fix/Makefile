ARCHS = arm64
TARGET = iphone:clang:16.5:16.3

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = UnscrollRuntimeFix

UnscrollRuntimeFix_FILES = UnscrollRuntimeFix.m
UnscrollRuntimeFix_FRAMEWORKS = Foundation Security
UnscrollRuntimeFix_CFLAGS = -fobjc-arc
UnscrollRuntimeFix_INSTALL_PATH = @executable_path/Frameworks

include $(THEOS_MAKE_PATH)/library.mk
