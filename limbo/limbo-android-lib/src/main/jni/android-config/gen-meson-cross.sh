#!/usr/bin/env bash
#
# Meson 크로스 파일 생성기.
#
# QEMU 5.2+ 및 glib 2.58+, pixman 0.40+, libslirp 는 모두 Meson 으로 빌드된다.
# 이 스크립트는 NDK 툴체인과 ABI 정보를 받아 Meson 크로스 파일을 만든다.
#
# 사용법:
#   gen-meson-cross.sh <ABI> <NDK_ROOT> <API> <PREFIX> <출력파일>
#
#   ABI     arm64-v8a | x86_64      (32비트 ABI는 QEMU 11에서 지원되지 않음)
#   API     안드로이드 API 레벨 (예: 23)
#   PREFIX  크로스 빌드된 의존성이 설치되는 접두사
#
set -euo pipefail

ABI="${1:?ABI required}"
NDK_ROOT="${2:?NDK_ROOT required}"
API="${3:?API level required}"
PREFIX="${4:?install prefix required}"
OUT="${5:?output file required}"

case "$ABI" in
    arm64-v8a)
        TRIPLE=aarch64-linux-android
        CPU_FAMILY=aarch64
        CPU=aarch64
        ;;
    x86_64)
        TRIPLE=x86_64-linux-android
        CPU_FAMILY=x86_64
        CPU=x86_64
        ;;
    armeabi-v7a|x86)
        echo "error: $ABI is a 32-bit ABI." >&2
        echo "       QEMU 11.0 removed all 32-bit host support" \
             "(docs/about/removed-features.rst)." >&2
        echo "       Use QEMU 5.1.0 legacy builds for 32-bit devices." >&2
        exit 1
        ;;
    *)
        echo "error: unknown ABI '$ABI'" >&2
        exit 1
        ;;
esac

HOST_TAG="$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64"
BIN="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG/bin"

if [ ! -x "$BIN/${TRIPLE}${API}-clang" ]; then
    echo "error: $BIN/${TRIPLE}${API}-clang not found." >&2
    echo "       Check NDK_ROOT and NDK_PLATFORM_API." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<EOF
# 자동 생성됨 - gen-meson-cross.sh. 직접 수정하지 말 것.
# ABI=$ABI API=$API NDK=$NDK_ROOT

[binaries]
c          = '$BIN/${TRIPLE}${API}-clang'
cpp        = '$BIN/${TRIPLE}${API}-clang++'
ar         = '$BIN/llvm-ar'
nm         = '$BIN/llvm-nm'
strip      = '$BIN/llvm-strip'
ranlib     = '$BIN/llvm-ranlib'
objcopy    = '$BIN/llvm-objcopy'
pkg-config = 'pkg-config'
pkgconfig  = 'pkg-config'

[built-in options]
# Android 15+ 는 16KB 페이지를 쓰는 기기가 있으므로 정렬을 강제한다.
c_link_args   = ['-Wl,-z,max-page-size=16384']
cpp_link_args = ['-Wl,-z,max-page-size=16384']
prefix        = '$PREFIX'
libdir        = 'lib'

[properties]
# 크로스 환경에서 실행 검사를 할 수 없는 항목들의 사전 답안.
needs_exe_wrapper = true
pkg_config_libdir = '$PREFIX/lib/pkgconfig'

# 주의: sys_root 를 지정하면 안 된다.
# 크로스 빌드한 의존성은 NDK sysroot 바깥의 \$PREFIX 에 설치되는데,
# sys_root 가 설정되면 pkg-config 가 돌려주는 -I/-L 경로 앞에
# sysroot 를 덧붙여서 (-I<sysroot><prefix>/include) 헤더를 못 찾는다.

# glib 이 크로스 빌드에서 물어보는 실행 검사 결과.
growing_stack       = false
have_c99_vsnprintf  = true
have_c99_snprintf   = true
have_unix98_printf  = true

[host_machine]
# QEMU configure 는 __linux__ 매크로로 호스트 OS 를 판별하므로
# system 은 'android' 가 아니라 'linux' 여야 CONFIG_LINUX 경로를 탄다.
system     = 'linux'
subsystem  = 'android'
kernel     = 'linux'
cpu_family = '$CPU_FAMILY'
cpu        = '$CPU'
endian     = 'little'
EOF

echo "wrote $OUT"
