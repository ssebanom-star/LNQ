# QEMU 11.0.3 Android 크로스 빌드 — 실측 결과

날짜: 2026-08-01
결론: **`libqemu-system-x86_64.so` (Android arm64, APK 탑재 가능) 빌드 성공**

계획서([`limbo-x86-qemu11-port-plan.md`](limbo-x86-qemu11-port-plan.md))의 Phase 0~2를 실제로 수행한 기록이다.
계획 단계에서 예측하지 못했던 문제가 여럿 나왔고, 그 해결책이 전부 저장소에 반영되어 있다.

---

## 1. 빌드 환경

| 항목 | 값 |
|---|---|
| 호스트 | Linux x86_64, Ubuntu 24.04 |
| NDK | r27c (clang 18.0.3) |
| 타깃 | `aarch64-linux-android28` (arm64-v8a, API 28) |
| meson / ninja / python | 1.11.2 / 1.11.1 / 3.11.15 |
| QEMU | 11.0.3 (`https://download.qemu.org/qemu-11.0.3.tar.xz`) |
| 게스트 | `x86_64-softmmu` |

---

## 2. 산출물 검증

```
$ file libqemu-system-x86_64.so
ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked

$ llvm-readelf -d libqemu-system-x86_64.so | grep -E 'SONAME|NEEDED'
  (NEEDED)  Shared library: [libm.so]
  (NEEDED)  Shared library: [libdl.so]
  (NEEDED)  Shared library: [libc.so]
  (SONAME)  Library soname: [libqemu-system-x86_64.so]

$ llvm-nm -D --defined-only libqemu-system-x86_64.so | grep -E 'qemu_(init|main_loop|cleanup|system_)'
T qemu_cleanup
T qemu_init
T qemu_main_loop
T qemu_system_reset_request
T qemu_system_shutdown_request

$ llvm-nm -D --defined-only libqemu-system-x86_64.so | grep -E 'gui_refresh|vnc_refresh|limbo_'
D gui_refresh_interval_default
D gui_refresh_interval_idle
B limbo_vga_full_update
D vnc_refresh_interval_base
D vnc_refresh_interval_inc

$ llvm-readelf -l libqemu-system-x86_64.so | grep -m1 LOAD
  LOAD  ...  R  0x4000          # 16KB 페이지 정렬 OK

$ llvm-strip -o q.so libqemu-system-x86_64.so && stat -c%s q.so
34416616                        # 약 34 MB
```

체크포인트 전부 통과:

- **NEEDED가 플랫폼 라이브러리 3개뿐** — glib/pixman/libslirp/pcre2/libffi는 전부 정적 링크
- **SONAME에 버전 접미사 없음** — APK 탑재 가능 (§3.1 참조)
- **JNI 진입점 5개 모두 export**
- **Limbo 런타임 튜닝 전역 변수 모두 export**
- **LOAD 정렬 0x4000 = 16 KB** — Android 15+ 16KB 페이지 기기 대응

---

## 3. 계획서에 없던 실제 문제와 해결

### 3.1 ★ 의존성 SONAME 버전 접미사 (APK 탑재 불가)

가장 위험했던 문제. glib을 **공유** 라이브러리로 빌드하면 링크·실행 모두 정상처럼 보이지만,

```
(NEEDED)  libglib-2.0.so.0
(NEEDED)  libpixman-1.so.0
(NEEDED)  libz.so.1
```

**Android 패키지 설치기는 APK에서 `lib*.so` 형태만 추출한다.** `.so.0`으로 끝나는 파일은
`jniLibs/`에 넣어도 기기에 풀리지 않으므로 `dlopen`이 런타임에 실패한다. 빌드 성공 →
기기에서 로드 실패라는, 디버깅하기 가장 나쁜 형태의 실패다.

**해결**: glib · pixman · libslirp를 `--default-library static`으로 크로스 빌드하여
에뮬레이터 `.so`에 정적으로 흡수. zlib만 NDK sysroot의 플랫폼 `libz`(버전 없음, 모든 기기에 존재)를
`.pc` 파일로 가리킨다. → `android-config/build-deps.sh`

### 3.2 `-Dprefer_static=true`가 bionic libc까지 정적 링크

3.1의 해결책으로 처음에 `-Dprefer_static=true`를 썼더니:

```
ld.lld: error: duplicate symbol: memfd_create
>>> defined at util/memfd.c:40 (libqemuutil.a)
>>> defined at syscalls-arm64.S:628 (libc.a)
```

meson의 `prefer_static`은 **libc를 포함한 모든 라이브러리**에 적용된다. bionic의 `libc.a`에는
`memfd_create` 심볼이 있지만 헤더는 API 30부터만 선언하므로, QEMU의 `CONFIG_MEMFD` 탐지가
실패해 자체 정의를 넣고 충돌한다.

**해결**: `prefer_static`을 쓰지 않는다. `$(LIMBO_PREFIX)/lib`에 `.a`만 두면 `-lglib-2.0`이
어차피 정적으로만 해석되므로 옵션 자체가 불필요하다. → `android-qemu-config-11.0.3.mak`에 경고와 함께 명시

### 3.3 `-shared`와 `-pie` 충돌

QEMU의 `project()`가 `b_pie=true`를 기본으로 두는데, 공유 라이브러리에는 PIE가 무의미하다.

```
ld.lld: error: -shared and -pie may not be used together
```

**해결**: `--disable-pie`

### 3.4 정적 라이브러리 PIC 누락

QEMU의 `project()`는 `b_staticpic=false`다.

```
ERROR: Can't link non-PIC static library 'qemuutil' into shared library
```

**해결**: `-Db_staticpic=true`

### 3.5 bionic에 `librt`와 POSIX 공유 메모리가 없음

```
meson.build:1367: ERROR: C shared or static library 'rt' not found
```

glibc가 `librt`에 두는 것들이 bionic에서는 libc 안에 있고, `shm_open`은 아예 없다
(Android는 ashmem/memfd를 쓴다).

**해결**: `meson.build`에 bionic 탐지(`__BIONIC__`, `<sys/cdefs.h>` 경유)를 추가해 `librt` 요구를 건너뛰고,
`util/oslib-posix.c`의 `qemu_shm_alloc()`을 bionic에서 명시적 에러로 스텁 처리.
(`-object memory-backend-shm`은 Limbo가 쓰지 않는다.)

> 주의: `cc.get_define('__BIONIC__')`만으로는 안 된다. `__BIONIC__`은 컴파일러 내장 매크로가 아니라
> `<sys/cdefs.h>`에 있으므로 `prefix:`로 헤더를 넣어줘야 한다.

### 3.6 ★ SCSI 상태 코드 매크로 충돌 — 값이 실제로 다름

```
include/scsi/constants.h:171: error: 'CHECK_CONDITION' macro redefined
  (previous definition: <NDK>/sysroot/usr/include/scsi/sg.h:60)
```

단순 중복이 아니다. **값이 다르다**:

| 매크로 | NDK `<scsi/sg.h>` | QEMU |
|---|---|---|
| `CHECK_CONDITION` | `0x01` | `0x02` |
| `BUSY` | `0x04` | `0x08` |
| `COMMAND_TERMINATED` | `0x11` | `0x22` |

QEMU는 SAM 규격의 left-shifted 인코딩을, Linux UAPI는 shift 안 된 인코딩을 쓴다.
`-Wno-macro-redefined`로 경고만 끄면 **ATAPI/SCSI 상태 바이트가 조용히 깨진다.**

**해결**: `include/scsi/constants.h`에서 해당 매크로들을 `#undef` 후 QEMU 값으로 재정의.

### 3.7 `getrandom(NULL, 0, 0)` 프로브가 `-Wnonnull`에 걸림

bionic이 `getrandom`의 첫 인자를 `_Nonnull`로 어노테이트하는데 QEMU는 `-Werror`로 빌드한다.
길이 0 프로브라 버퍼는 역참조되지 않지만 컴파일이 안 된다.

**해결**: 실제 객체의 주소를 넘긴다 (`char probe; getrandom(&probe, 0, 0)`).

### 3.8 `__LITTLE_ENDIAN_BITFIELD` 재정의

`hw/net/can/ctucan_core.h`가 무조건 정의하는데 bionic의 `<linux/stddef.h>`에 이미 있다.

**해결**: `#ifndef` 가드.

### 3.9 vhost-user / VDUSE가 bionic에서 빌드 불가

번들된 `standard-headers/linux/virtio_ring.h`가 NDK UAPI 헤더와 구조체 정의를 중복하고,
`libvhost-user.c`가 `memfd_create`를 선언 없이 호출한다.

**해결**: Limbo에서 도달 불가능한 기능이므로 전부 비활성화
(`--disable-vhost-user --disable-libvduse` 등).

### 3.10 `pkg-config`가 `--cross-prefix`를 따라감

```
WARNING: We thought we found pkg-config 'llvm-pkg-config' but now it's not there.
ERROR: Dependency lookup for glib-2.0 ... Pkg-config for machine host machine not found
```

QEMU configure는 `pkg_config="${PKG_CONFIG-${cross_prefix}pkg-config}"`로 유도하는데
NDK에는 `llvm-pkg-config`가 없다.

**해결**: `PKG_CONFIG=pkg-config`를 환경에 명시하고, `PKG_CONFIG_LIBDIR`로 탐색 범위를
크로스 prefix로 좁힌다. → `android-limbo-build.mak`의 `PKG_CONFIG_ENV`

### 3.11 meson 크로스 파일에 `sys_root`를 넣으면 안 됨

`[properties] sys_root`를 지정하면 pkg-config가 돌려주는 `-I`/`-L` 경로 앞에 sysroot를 덧붙인다.
크로스 빌드한 의존성은 NDK sysroot **바깥**에 있으므로 `-I<sysroot><prefix>/include`가 되어
헤더를 못 찾는다. → `gen-meson-cross.sh`에 주석으로 명시

### 3.12 API 21로는 glib 2.66+ 빌드 불가

```
glib-2.84.0/meson.build:2224: ERROR: Dependency "iconv" not found (tried builtin and system)
```

bionic은 **API 28부터** `iconv_open`/`iconv`/`iconv_close`를 제공한다
(`<iconv.h>`의 `__INTRODUCED_IN(28)`).

**해결**: `minSdkVersion`을 21 → **28**로 상향. 부수 효과로 `memfd_create`, `getrandom`,
`strchrnul`도 네이티브로 쓸 수 있어 Limbo의 오래된 libc 셰임 상당수가 필요 없어진다.

### 3.13 pcre2 JIT가 bionic에서 빌드 불가

glib의 pcre2 subproject가 `secure_getenv`를 호출한다(bionic에 없음). Android의 W^X 정책상
JIT 페이지 자체가 문제이기도 하다.

**해결**: `-Dpcre2:jit=disabled`

---

## 4. 확정된 configure 명령

`android-config/android-qemu-config-11.0.3.mak`가 생성하는 것과 동일하다.

```sh
export PKG_CONFIG=pkg-config
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig

$QEMU_SRC/configure \
  --target-list=x86_64-softmmu \
  --cc=$NDK/bin/aarch64-linux-android28-clang \
  --cxx=$NDK/bin/aarch64-linux-android28-clang++ \
  --cross-prefix=$NDK/bin/llvm- --cpu=aarch64 \
  --enable-slirp --enable-vnc --with-coroutine=sigaltstack \
  --disable-pie --disable-fdt --disable-rust --disable-plugins \
  --disable-vhost-user --disable-libvduse --disable-multiprocess ... \
  -Dshared_emulator=true -Db_staticpic=true \
  --extra-cflags="-D__LIMBO__ ..." \
  --extra-ldflags="-Wl,-z,max-page-size=16384 ..."
```

---

## 5. 남은 작업

| 항목 | 상태 |
|---|---|
| `x86_64-softmmu` arm64-v8a 빌드 | **완료** |
| `x86_64` ABI 빌드 | 미실행 (같은 파이프라인, ABI만 교체) |
| SDL 프론트엔드 | **미완** — `sdl2-2.0.8.patch`를 SDL2 2.32로 포워드포팅 필요. 현재는 VNC 전용 |
| `ui/sdl2.c` Limbo 훅 | SDL 활성화 후 적용 (렌더러 강제, scale hint, NULL console 가드, 해상도 콜백) |
| `monitor/fds.c` SAF fd 패스스루 | 미적용 |
| `__wrap_*` SAF 파일 접근 구현 | 링커 플래그는 배선 완료, `compat/`에 `__wrap_open` 등 구현 필요 |
| ndk-build 쪽 (compat, SDL2, JNI) | 미검증 |
| 실기기 부팅 테스트 | 미실행 |

SDL·SAF·실기기 검증이 남아 있으므로 **아직 동작하는 APK는 아니다.** 다만 가장 불확실했던
"QEMU 11을 Android용 공유 라이브러리로 만들 수 있는가"는 확인됐다.
