LIMBO_JNI_ROOT := $(CURDIR)/jni

include $(LIMBO_JNI_ROOT)/android-limbo-build.mak

#Suppress Format errors from logutils.h macros
APP_CFLAGS += -Wno-format-security -Wno-macro-redefined

#Debug/Release
ifeq ($(NDK_DEBUG),1)
    APP_OPTIM := debug
else
    APP_OPTIM := release
endif

#Don't remove this
APP_CFLAGS += -include $(LOGUTILS)
APP_LDFLAGS += -llog

# Android 15 runs on devices with 16 KB pages, and the loader rejects a
# shared library whose LOAD segments are only 4 KB aligned. QEMU's own link
# gets this from QEMU_LDFLAGS; ndk-build needs telling separately.
APP_LDFLAGS += -Wl,-z,max-page-size=16384

APP_ARM_MODE=$(ARM_MODE)

$(info NDK_TOOLCHAIN_VERSION = $(NDK_TOOLCHAIN_VERSION))
$(info NDK_DEBUG = $(NDK_DEBUG))
$(info APP_ARM_MODE = $(APP_ARM_MODE))
$(info APP_ARM_NEON = $(APP_ARM_NEON))
$(info APP_OPTIM = $(APP_OPTIM))
$(info APP_ABI = $(APP_ABI))
$(info APP_PLATFORM = $(APP_PLATFORM))
$(info NDK_PROJECT_PATH = $(NDK_PROJECT_PATH))
$(info ARCH_CFLAGS = $(ARCH_CFLAGS))
$(info APP_CFLAGS = $(APP_CFLAGS))
