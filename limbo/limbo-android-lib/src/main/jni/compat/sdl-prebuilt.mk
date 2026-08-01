# Import the libSDL2.so that android-config/build-deps.sh cross-built into
# $(LIMBO_PREFIX), so ndk-build links against the exact same binary that QEMU
# was linked against.
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := SDL2
LOCAL_SRC_FILES := $(LIMBO_PREFIX_ABS)/lib/libSDL2.so
LOCAL_EXPORT_C_INCLUDES := $(LIMBO_PREFIX_ABS)/include/SDL2
include $(PREBUILT_SHARED_LIBRARY)
