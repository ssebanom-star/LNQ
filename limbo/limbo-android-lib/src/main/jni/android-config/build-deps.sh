#!/usr/bin/env bash
#
# Cross-compiles QEMU 11's mandatory dependencies for Android.
#
#   glib      >= 2.66 is required by QEMU 11 (meson.build: glib_req_ver)
#   pixman    >= 0.21.8, required once VNC/GTK/SPICE is enabled
#   libslirp          user-mode networking; QEMU stopped vendoring slirp in 8.0
#   zlib              mandatory (meson.build: dependency('zlib', required: true))
#
# Everything is built as a *static* archive and linked into
# libqemu-system-*.so. That is deliberate: meson gives shared libraries a
# versioned soname (libglib-2.0.so.0), and Android's package installer only
# extracts unversioned lib*.so files from an APK -- a shared glib would build
# fine and then fail to load on device.
#
# zlib is the exception: the NDK sysroot's libz is already an unversioned
# platform library present on every device, so we just point pkg-config at it.
#
# Usage:
#   build-deps.sh <ABI> <NDK_ROOT> <API> <PREFIX> [SRC_CACHE]
#
set -euo pipefail

ABI="${1:?ABI required (arm64-v8a|x86_64)}"
NDK_ROOT="${2:?NDK_ROOT required}"
API="${3:?API level required}"
PREFIX="${4:?install prefix required}"
SRC="${5:-$PREFIX/src}"

HERE="$(cd "$(dirname "$0")" && pwd)"

GLIB_VER=2.84.0
GLIB_SERIES=2.84
PIXMAN_VER=0.44.2
SLIRP_VER=4.9.1
SDL_VER=2.32.4

case "$ABI" in
    arm64-v8a) TRIPLE=aarch64-linux-android ;;
    x86_64)    TRIPLE=x86_64-linux-android ;;
    *) echo "error: $ABI is not a supported 64-bit ABI" >&2; exit 1 ;;
esac

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

mkdir -p "$PREFIX/lib/pkgconfig" "$SRC"
CROSS="$PREFIX/meson-cross-$ABI.ini"
"$HERE/gen-meson-cross.sh" "$ABI" "$NDK_ROOT" "$API" "$PREFIX" "$CROSS"

export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH=

fetch() {
    local url="$1" out="$SRC/$2"
    [ -f "$out" ] || { log "fetch $(basename "$url")"; curl -fSL --retry 3 -o "$out" "$url"; }
}

######################################################################
# zlib: describe the NDK's platform libz to pkg-config
######################################################################
SYSROOT="$NDK_ROOT/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64/sysroot"
log "writing zlib.pc for the platform libz"
cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<EOF
prefix=$SYSROOT/usr
includedir=\${prefix}/include
libdir=\${prefix}/lib/$TRIPLE/$API
Name: zlib
Description: Android platform zlib (NDK sysroot)
Version: 1.2.13
Libs: -lz
Cflags: -I\${includedir}
EOF

######################################################################
# glib (pulls in libffi, pcre2 and proxy-libintl as meson subprojects)
######################################################################
if [ ! -f "$PREFIX/lib/pkgconfig/glib-2.0.pc" ]; then
    fetch "https://download.gnome.org/sources/glib/$GLIB_SERIES/glib-$GLIB_VER.tar.xz" "glib-$GLIB_VER.tar.xz"
    [ -d "$SRC/glib-$GLIB_VER" ] || tar -xJf "$SRC/glib-$GLIB_VER.tar.xz" -C "$SRC"
    log "building glib $GLIB_VER"
    # -Dnls=disabled avoids needing gettext tooling on the build host; QEMU
    #  does not use glib's translations.
    # -Dpcre2:jit=disabled because pcre2's sljit allocator calls
    #  secure_getenv(), which bionic does not provide (and W^X would block
    #  JIT pages on Android anyway).
    meson setup "$SRC/glib-build-$ABI" "$SRC/glib-$GLIB_VER" \
        --cross-file "$CROSS" --prefix "$PREFIX" --libdir lib \
        --default-library static --buildtype release \
        --force-fallback-for=libffi,pcre2,proxy-libintl \
        -Dtests=false -Dglib_debug=disabled -Dintrospection=disabled \
        -Dman-pages=disabled -Ddocumentation=false -Dlibmount=disabled \
        -Dselinux=disabled -Dnls=disabled -Dsysprof=disabled \
        -Dpcre2:jit=disabled
    ninja -C "$SRC/glib-build-$ABI" install
fi

######################################################################
# pixman
######################################################################
if [ ! -f "$PREFIX/lib/pkgconfig/pixman-1.pc" ]; then
    fetch "https://www.cairographics.org/releases/pixman-$PIXMAN_VER.tar.gz" "pixman-$PIXMAN_VER.tar.gz"
    [ -d "$SRC/pixman-$PIXMAN_VER" ] || tar -xzf "$SRC/pixman-$PIXMAN_VER.tar.gz" -C "$SRC"
    log "building pixman $PIXMAN_VER"
    meson setup "$SRC/pixman-build-$ABI" "$SRC/pixman-$PIXMAN_VER" \
        --cross-file "$CROSS" --prefix "$PREFIX" --libdir lib \
        --default-library static --buildtype release \
        -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled
    ninja -C "$SRC/pixman-build-$ABI" install
fi

######################################################################
# libslirp
######################################################################
if [ ! -f "$PREFIX/lib/pkgconfig/slirp.pc" ]; then
    fetch "https://gitlab.freedesktop.org/slirp/libslirp/-/archive/v$SLIRP_VER/libslirp-v$SLIRP_VER.tar.gz" "libslirp-$SLIRP_VER.tar.gz"
    [ -d "$SRC/libslirp-v$SLIRP_VER" ] || tar -xzf "$SRC/libslirp-$SLIRP_VER.tar.gz" -C "$SRC"
    log "building libslirp $SLIRP_VER"
    meson setup "$SRC/slirp-build-$ABI" "$SRC/libslirp-v$SLIRP_VER" \
        --cross-file "$CROSS" --prefix "$PREFIX" --libdir lib \
        --default-library static --buildtype release
    ninja -C "$SRC/slirp-build-$ABI" install
fi

######################################################################
# SDL2
#
# Built with CMake rather than meson (SDL2 has no meson build) and left as a
# *shared* library: Limbo's Java layer needs SDLActivity, and
# compat/sdl-extensions links against it too. That is safe here because SDL2's
# CMake build produces an unversioned libSDL2.so soname, which an APK can carry.
#
# Expects the Limbo patch to have been applied already:
#   cd $SRC/SDL2-$SDL_VER && patch -p1 < <jni>/patches/sdl2-$SDL_VER.patch
######################################################################
if [ ! -f "$PREFIX/lib/pkgconfig/sdl2.pc" ]; then
    fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VER/SDL2-$SDL_VER.tar.gz" "SDL2-$SDL_VER.tar.gz"
    if [ ! -d "$SRC/SDL2-$SDL_VER" ]; then
        tar -xzf "$SRC/SDL2-$SDL_VER.tar.gz" -C "$SRC"
        log "applying $HERE/../patches/sdl2-$SDL_VER.patch"
        ( cd "$SRC/SDL2-$SDL_VER" && patch -p1 < "$HERE/../patches/sdl2-$SDL_VER.patch" )
    fi
    log "building SDL2 $SDL_VER"
    cmake -S "$SRC/SDL2-$SDL_VER" -B "$SRC/sdl-build-$ABI" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_ROOT/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF \
        -DCMAKE_C_FLAGS="-D__LIMBO__"
    cmake --build "$SRC/sdl-build-$ABI" -j"$(nproc)"
    cmake --install "$SRC/sdl-build-$ABI"
fi

log "done. pkg-config modules available in $PREFIX/lib/pkgconfig:"
ls "$PREFIX/lib/pkgconfig"
