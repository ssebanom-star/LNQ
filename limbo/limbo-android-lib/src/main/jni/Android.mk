# ndk-build modules: the Limbo-side native code.
#
# QEMU itself is NOT built here -- it is a meson/ninja build driven by the
# top-level Makefile. This file only covers the small libraries that the app
# loads directly.

#dep libs
include $(NDK_PROJECT_PATH)/jni/compat/Android.mk

ifeq ($(USE_SDL),true)
	include $(NDK_PROJECT_PATH)/jni/compat/sdl-prebuilt.mk
	include $(NDK_PROJECT_PATH)/jni/compat/sdl-extensions/Android.mk
endif

include $(NDK_PROJECT_PATH)/jni/limbo/Android.mk

# Dropped relative to upstream Limbo:
#
#   compat/musl        iconv/gettext shims. bionic provides iconv from API 28
#                      (this project's minimum) and glib links proxy-libintl
#                      statically, so the shims are dead code -- and defining
#                      iconv_open on top of bionic's is asking for trouble.
#
#   compat/sdl-addons  AAudio bridge for SDL 2.0.8. SDL has had a native
#                      AAudio backend since 2.0.14 and prefers it over the
#                      legacy Java AudioTrack driver.
#
#   SDL2/Android.mk    SDL2 is cross-built once by android-config/build-deps.sh
#                      (with CMake, because QEMU needs an sdl2.pc from it) and
#                      consumed here as a prebuilt -- see compat/sdl-prebuilt.mk.
#                      Building it twice would produce two different libSDL2.so.
