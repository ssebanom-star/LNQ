# Do not modify this file, all configuration is under directory android-config

LIMBO_JNI_ROOT:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
include $(LIMBO_JNI_ROOT)/android-config/android-limbo-config.mak

# prepend the NDK_ROOT in the path so the ndk-build is the correct one
PATH  := $(NDK_ROOT):$(PATH)
SHELL := env PATH=$(PATH) /bin/bash

#PLATFORM CONFIG
# Ideally App platform used to compile should be equal or lower than the minSdkVersion in AndroidManifest.xml
APP_PLATFORM = android-$(NDK_PLATFORM_API)

######################################################################
# Host ABI
#
# QEMU 11.0 dropped every 32-bit host backend -- there is no tcg/arm and no
# tcg/i386 any more -- so armeabi-v7a and x86 cannot be targeted at all.
# Fail loudly here instead of producing a confusing meson error later.
######################################################################

ifeq ($(BUILD_HOST),armeabi-v7a)
$(error BUILD_HOST=armeabi-v7a is not supported with QEMU $(USE_QEMU_VERSION). \
  QEMU 11.0 removed all 32-bit host support. Use arm64-v8a, or build the \
  QEMU 5.1.0 branch for 32-bit devices.)
endif
ifeq ($(BUILD_HOST),x86)
$(error BUILD_HOST=x86 is not supported with QEMU $(USE_QEMU_VERSION). \
  QEMU 11.0 removed all 32-bit host support. Use x86_64, or build the \
  QEMU 5.1.0 branch for 32-bit devices.)
endif

ifeq ($(BUILD_HOST), arm64-v8a)
######### ARMv8 64 bit
include $(LIMBO_JNI_ROOT)/android-config/android-device-config/android-armv8.mak
else ifeq ($(BUILD_HOST), x86_64)
######### x86_64
include $(LIMBO_JNI_ROOT)/android-config/android-device-config/android-x86_64.mak
else
$(error Unknown BUILD_HOST '$(BUILD_HOST)'. Valid values: arm64-v8a, x86_64)
endif

#SET/RESET vars
ARCH_CFLAGS := -D__LIMBO__ -D__ANDROID__ -DANDROID -D__linux__ -DCONFIG_LINUX \
  $(ARCH_CFLAGS)

ifeq ($(APP_ABI),arm64-v8a)
    HOST_PREFIX = aarch64-linux-android
    GNU_HOST = aarch64-linux-android
    MESON_CPU_FAMILY = aarch64
    TARGET_ARCH = arm64
    APP_ABI_DIR = $(APP_ABI)
else ifeq ($(APP_ABI),x86_64)
    HOST_PREFIX = x86_64-linux-android
    GNU_HOST = x86_64-linux-android
    MESON_CPU_FAMILY = x86_64
    TARGET_ARCH = x86_64
    APP_ABI_DIR = $(APP_ABI)
endif

######################################################################
# Toolchain (NDK r27+, clang only)
######################################################################

TOOLCHAIN_CLANG_DIR = $(NDK_ROOT)/toolchains/llvm/prebuilt/$(NDK_ENV)
TOOLCHAIN_CLANG_PREFIX := $(TOOLCHAIN_CLANG_DIR)/bin
NDK_PROJECT_PATH := $(LIMBO_JNI_ROOT)/../

# The NDK ships per-API wrapper scripts that bake in --target=<triple><api>,
# which is exactly the form QEMU's configure wants for --cc.
CC   = $(TOOLCHAIN_CLANG_PREFIX)/$(HOST_PREFIX)$(NDK_PLATFORM_API)-clang
CXX  = $(TOOLCHAIN_CLANG_PREFIX)/$(HOST_PREFIX)$(NDK_PLATFORM_API)-clang++
LNK  = $(CC)
AR   = $(TOOLCHAIN_CLANG_PREFIX)/llvm-ar
AS   = $(TOOLCHAIN_CLANG_PREFIX)/llvm-as
NM   = $(TOOLCHAIN_CLANG_PREFIX)/llvm-nm
OBJ_COPY = $(TOOLCHAIN_CLANG_PREFIX)/llvm-objcopy
STRIP    = $(TOOLCHAIN_CLANG_PREFIX)/llvm-strip
READELF  = $(TOOLCHAIN_CLANG_PREFIX)/llvm-readelf

# QEMU's configure derives ar/nm/strip/... from --cross-prefix; the NDK's
# llvm-* binaries match that naming, but note that llvm-pkg-config does NOT
# exist -- see PKG_CONFIG in android-limbo-config.mak.
CROSS_PREFIX = $(TOOLCHAIN_CLANG_PREFIX)/llvm-

SYSROOT = $(TOOLCHAIN_CLANG_DIR)/sysroot
SYS_ROOT = --sysroot=$(SYSROOT)
NDK_INCLUDE = $(SYSROOT)/usr/include

AR_FLAGS = crs

# INCLUDE_FIXED contains overrides for include files found under the toolchain's /usr/include.
# Currently we don't use, left here as a placeholder.
INCLUDE_FIXED = $(LIMBO_JNI_ROOT)/include-fixed

# The logutils header is injected into all compiled files in order to redirect
# output to the Android console, and provide debugging macros.
LOGUTILS = $(LIMBO_JNI_ROOT)/compat/limbo_logutils.h

#Some fixes for Android compatibility
COMPATUTILS_FD = $(LIMBO_JNI_ROOT)/compat/limbo_compat_filesystem.h
COMPATUTILS_QEMU = $(LIMBO_JNI_ROOT)/compat/limbo_compat_qemu.h
COMPATMACROS = $(LIMBO_JNI_ROOT)/compat/limbo_compat_macros.h
COMPATANDROID = $(LIMBO_JNI_ROOT)/compat/limbo_compat.h

# Headers force-included into every QEMU translation unit.
#
# Unlike the QEMU 5.1.0 build we no longer add -I<jni>/glib, -I<jni>/pixman
# and friends here: those libraries are now cross-built with meson into
# $(LIMBO_PREFIX), and QEMU picks their include paths up from pkg-config.
#
# limbo_compat_filesystem.h and limbo_compat.h are deliberately NOT forced in
# any more. They declare short, unprefixed names -- get_fd(), close_fd(),
# fd_t, jvm -- and injecting those into every QEMU file collides with QEMU's
# own statics; migration/vmstate-types.c has a static get_fd() and fails to
# compile. They were only needed when open() was redirected to android_open()
# by symbol renaming, which required the declaration to be visible. With the
# linker --wrap approach QEMU just calls plain open() and the redirection
# happens at link time, so the declarations are unnecessary.
SYSTEM_INCLUDE = \
    -I$(INCLUDE_FIXED) \
    -I$(LIMBO_JNI_ROOT)/compat \
    -include $(LOGUTILS) \
    -include $(COMPATUTILS_QEMU) \
    -include $(COMPATMACROS)

######################################################################
# Dependency prefix
######################################################################

# meson and pkg-config both need absolute paths here.
LIMBO_PREFIX_ABS := $(abspath $(LIMBO_PREFIX))

# Scoping pkg-config to our own prefix keeps the build machine's
# /usr/lib/pkgconfig out of the cross build. Without PKG_CONFIG_LIBDIR,
# QEMU cheerfully finds the host's glib and then fails at link time.
PKG_CONFIG_ENV = \
    PKG_CONFIG=$(PKG_CONFIG) \
    PKG_CONFIG_LIBDIR=$(LIMBO_PREFIX_ABS)/lib/pkgconfig \
    PKG_CONFIG_PATH=

MESON_CROSS_FILE = $(LIMBO_PREFIX_ABS)/meson-cross-$(APP_ABI).ini

#info
$(info VARIABLES)
$(info NDK_ROOT = $(NDK_ROOT))
$(info APP_PLATFORM = $(APP_PLATFORM))
$(info NDK_PLATFORM_API = $(NDK_PLATFORM_API))
$(info APP_ABI = $(APP_ABI))
$(info USE_OPTIMIZATION = $(USE_OPTIMIZATION))
$(info USE_SECURITY = $(USE_SECURITY))
$(info BUILD_THREADS = $(BUILD_THREADS))
$(info NDK_ENV = $(NDK_ENV))
$(info BUILD_HOST = $(BUILD_HOST))
$(info BUILD_GUEST = $(BUILD_GUEST))
$(info USE_QEMU_VERSION = $(USE_QEMU_VERSION))
$(info LIMBO_PREFIX = $(LIMBO_PREFIX_ABS))
$(info USE_SDL = $(USE_SDL))
$(info USE_SDL_AUDIO = $(USE_SDL_AUDIO))
$(info USE_AAUDIO = $(USE_AAUDIO))
$(info USE_KVM = $(USE_KVM))
