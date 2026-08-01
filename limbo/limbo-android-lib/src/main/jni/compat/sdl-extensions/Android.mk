LOCAL_PATH:= $(call my-dir)

include $(CLEAR_VARS)

LOCAL_SRC_FILES := \
	SDL_limbomouse.c \
	SDL_limboscreen.c

LOCAL_MODULE := compat-SDL2-ext

# These files reach into SDL's *internal* headers (src/SDL_internal.h,
# events/SDL_mouse_c.h, core/android/SDL_android.h), which are not part of the
# installed API, so the SDL source tree has to be on the include path -- the
# installed headers in $(LIMBO_PREFIX)/include/SDL2 are not enough.
LOCAL_C_INCLUDES :=			\
	$(LIMBO_JNI_ROOT)/SDL2 \
	$(LIMBO_JNI_ROOT)/SDL2/src \
	$(LIMBO_JNI_ROOT)/SDL2/include

LOCAL_CFLAGS += -D__LIMBO__

LOCAL_SHARED_LIBRARIES += SDL2

include $(BUILD_SHARED_LIBRARY)
