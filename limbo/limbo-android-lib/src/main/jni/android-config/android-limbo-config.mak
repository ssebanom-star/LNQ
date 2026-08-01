############### Limbo Configuration ##############
# if the  makefile doesn't recognize the project path you can override it here:
#LIMBO_JNI_ROOT := /home/dev/limbo/workspace_limbo/limbo-android-lib/src/main/jni

# NDK r27 or newer. gcc support was dropped: the last NDK that shipped gcc
# was r14b, and QEMU 11 cannot be built with it.
NDK_ROOT ?= /home/dev/tools/ndk/android-ndk-r27c

### the ndk api should be the same as the minSdkVersion in your AndroidManifest.xml
#
# API 28 is a floor, not a preference:
#   - bionic only provides iconv() from API 28, and glib >= 2.66 (required by
#     QEMU 11) needs it. Below 28 you are back to shipping an iconv shim.
#   - memfd_create, getrandom and strchrnul also arrive by 28, which removes
#     most of Limbo's historical libc workarounds.
NDK_PLATFORM_API ?= 28

# Optimization, generally it is better set to false when debugging
USE_OPTIMIZATION ?= true

# Hardening: it produces slower runtimes but helps preventing buffer overflow attacks
USE_SECURITY ?= true

# Uncomment to enable debugging
# If you enable debugging you should turn off optimization as well
#NDK_DEBUG=1

# Host (build machine) tag used to locate the NDK prebuilt toolchain.
# Compiling on Windows is not supported.
#NDK_ENV ?= darwin-x86_64
NDK_ENV ?= linux-x86_64

# Build threads (make -j ?) makes building faster
BUILD_THREADS ?= 4

############## QEMU Host and Guest

# Android device type (host arch)
#
# values: arm64-v8a, x86_64
#
# 32-bit ABIs (armeabi-v7a, x86) are NOT supported with QEMU 11.
# QEMU 11.0 removed every 32-bit host: there is no tcg/arm or tcg/i386
# backend left, and meson.build aborts with
#   "QEMU emulator requires a 64-bit CPU host architecture".
# See docs/about/removed-features.rst, "32-bit host operating systems".
# Keep building the QEMU 5.1.0 branch if you need to support 32-bit devices.
BUILD_HOST ?= arm64-v8a

# GUEST_ARCH is the Emulator type
# values: x86_64-softmmu,aarch64-softmmu,sparc64-softmmu,ppc64-softmmu
BUILD_GUEST ?= x86_64-softmmu

# QEMU Version
# values: 11.0.3
USE_QEMU_VERSION ?= 11.0.3

# Where the cross-compiled dependencies (glib, pixman, libslirp, SDL2...)
# are installed. QEMU locates them through PKG_CONFIG_LIBDIR.
LIMBO_PREFIX ?= $(LIMBO_JNI_ROOT)/../obj/prefix/$(BUILD_HOST)

# Host pkg-config binary. It must NOT carry the NDK triple prefix: QEMU's
# configure defaults to "$(cross_prefix)pkg-config", which does not exist in
# the NDK. We point PKG_CONFIG at the real one and scope its search path with
# PKG_CONFIG_LIBDIR instead.
PKG_CONFIG ?= pkg-config

# If you want to use SDL interface
USE_SDL ?= true

# If you want to use SDL Audio with Android AudioTrack
USE_SDL_AUDIO ?= true

# if you want to use Android AAudio, it needs version platform API 26
USE_AAUDIO ?= true

# Enable KVM
# Note: virtually no retail Android device exposes /dev/kvm. QEMU falls back
# to TCG at runtime when the ioctl fails, so leaving this enabled is harmless.
USE_KVM ?= true
