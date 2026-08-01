#!/usr/bin/env bash
#
# Limbo x86 → QEMU 11 포팅 작업용 소스 취득 스크립트.
# docs/limbo-x86-qemu11-port-plan.md 의 Phase 0 에 해당한다.
#
# 사용법:
#   ./scripts/fetch-sources.sh [작업디렉터리]
#
# 기본 작업디렉터리는 ./work 이다.
set -euo pipefail

WORKDIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/work}"

LIMBO_REPO="https://github.com/limboemu/limbo.git"
LIMBO_BRANCH="master"

QEMU_VERSION="11.0.3"
QEMU_URL="https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz"

# Phase 1 에서 크로스 빌드할 의존성들.
GLIB_URL="https://download.gnome.org/sources/glib/2.84/glib-2.84.0.tar.xz"
PIXMAN_URL="https://www.cairographics.org/releases/pixman-0.44.2.tar.gz"
LIBFFI_URL="https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz"
SDL2_URL="https://github.com/libsdl-org/SDL/releases/download/release-2.32.4/SDL2-2.32.4.tar.gz"
SLIRP_URL="https://gitlab.freedesktop.org/slirp/libslirp/-/archive/v4.9.1/libslirp-v4.9.1.tar.gz"
DTC_URL="https://git.kernel.org/pub/scm/utils/dtc/dtc.git/snapshot/dtc-1.7.2.tar.gz"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

fetch() {
    local url="$1" out="$2"
    if [ -f "$out" ]; then
        log "이미 있음: $(basename "$out")"
        return
    fi
    log "다운로드: $url"
    curl -fSL --retry 3 -o "$out.tmp" "$url"
    mv "$out.tmp" "$out"
}

mkdir -p "$WORKDIR/tarballs"
cd "$WORKDIR"

# ---------------------------------------------------------------- Limbo
if [ -d limbo/.git ]; then
    log "limbo 저장소 갱신"
    git -C limbo fetch origin "$LIMBO_BRANCH"
else
    log "limbo 클론 ($LIMBO_BRANCH)"
    git clone --branch "$LIMBO_BRANCH" "$LIMBO_REPO" limbo
fi

log "limbo HEAD: $(git -C limbo rev-parse --short HEAD)"
log "limbo 앱 버전: $(cat limbo/VERSION)"
log "limbo 번들 QEMU: $(grep -E '^USE_QEMU_VERSION' \
    limbo/limbo-android-lib/src/main/jni/android-config/android-limbo-config.mak)"

# ---------------------------------------------------------------- QEMU 11
fetch "$QEMU_URL" "tarballs/qemu-${QEMU_VERSION}.tar.xz"
if [ ! -d "qemu-${QEMU_VERSION}" ]; then
    log "QEMU ${QEMU_VERSION} 압축 해제 (약 900MB)"
    tar -xJf "tarballs/qemu-${QEMU_VERSION}.tar.xz"
fi

# ---------------------------------------------------------------- 의존성
for entry in \
    "$GLIB_URL|glib.tar.xz" \
    "$PIXMAN_URL|pixman.tar.gz" \
    "$LIBFFI_URL|libffi.tar.gz" \
    "$SDL2_URL|SDL2.tar.gz" \
    "$SLIRP_URL|libslirp.tar.gz" \
    "$DTC_URL|dtc.tar.gz"
do
    fetch "${entry%%|*}" "tarballs/${entry##*|}"
done

cat <<EOF

$(log "완료")

작업 디렉터리: $WORKDIR
  limbo/                 Limbo 소스 (master)
  qemu-${QEMU_VERSION}/  포팅 대상 QEMU
  tarballs/              의존성 아카이브

다음 단계는 docs/limbo-x86-qemu11-port-plan.md 의 Phase 0 체크리스트를 참고할 것.
빌드에는 Linux 호스트 + Android NDK r27/r28 + meson>=1.5 + ninja + python>=3.9 이 필요하다.
EOF
