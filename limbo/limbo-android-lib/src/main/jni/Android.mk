#include $(call all-subdir-makefiles)

#dep libs
include $(NDK_PROJECT_PATH)/jni/compat/musl/Android.mk
include $(NDK_PROJECT_PATH)/jni/compat/Android.mk
# compat/sdl-addons was Limbo's AAudio bridge for SDL 2.0.8, which could only
# reach Android audio through Java AudioTrack. SDL 2.32 has a native AAudio
# driver, so the bridge is dead code; see patches/sdl2-2.32.4.patch.
ifeq ($(USE_AAUDIO),true)
	$(error USE_AAUDIO is obsolete with SDL 2.32 - unset it)
endif

ifeq ($(USE_SDL),true)
	include $(NDK_PROJECT_PATH)/jni/SDL2/Android.mk
endif
include $(NDK_PROJECT_PATH)/jni/compat/sdl-extensions/Android.mk
include $(NDK_PROJECT_PATH)/jni/limbo/Android.mk

#Optional libs
#include $(NDK_PROJECT_PATH)/jni/png/Android.mk
#include $(NDK_PROJECT_PATH)/jni/jpeg/Android.mk

#TODO: For Spice
#include $(NDK_PROJECT_PATH)/jni/openssl/Android.mk
#include $(NDK_PROJECT_PATH)/jni/spice/Android.mk
