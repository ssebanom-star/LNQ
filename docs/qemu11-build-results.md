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

최종 빌드(SDL + VNC + slirp, SAF `--wrap` 후킹 포함) 기준.

```
$ file libqemu-system-x86_64.so
ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked

$ llvm-readelf -d libqemu-system-x86_64.so | grep -E 'SONAME|NEEDED'
  (NEEDED)  Shared library: [libcompat-limbo.so]
  (NEEDED)  Shared library: [liblog.so]
  (NEEDED)  Shared library: [libm.so]
  (NEEDED)  Shared library: [libz.so]
  (NEEDED)  Shared library: [libSDL2.so]
  (NEEDED)  Shared library: [libdl.so]
  (NEEDED)  Shared library: [libc.so]
  (SONAME)  Library soname: [libqemu-system-x86_64.so]

$ llvm-nm -D -u libqemu-system-x86_64.so | grep __wrap_
  U __wrap_close
  U __wrap_fopen
  U __wrap_mkstemp
  U __wrap_open
  U __wrap_stat

$ llvm-nm -D -u libqemu-system-x86_64.so | grep -E '^ +U (open|fopen|mkstemp)$'
  (없음 - 전부 __wrap_* 로 리디렉션됨)

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
34388264                        # 약 34 MB
```

체크포인트 전부 통과:

- **NEEDED가 전부 버전 접미사 없는 이름** — Android 플랫폼 라이브러리이거나 Limbo 자체 라이브러리.
  glib/pixman/libslirp/pcre2/libffi는 정적 링크되어 아예 나타나지 않는다
- **`--wrap` 리디렉션이 실제로 적용됨** — 평문 `open`/`fopen`/`mkstemp` 참조가 남아 있지 않다
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

## 3-B. SDL 프론트엔드 포팅에서 나온 것들

### 3-B.1 ★ Limbo의 AAudio 브리지가 통째로 불필요해짐

`sdl2-2.0.8.patch`의 절반 이상(약 110줄)은 `src/core/android/SDL_android.c`에
AAudio 브리지를 심는 코드였다. SDL 2.0.8이 Android 오디오에 Java `AudioTrack`으로만
접근할 수 있었기 때문에, Limbo가 별도 `.so`(`compat/sdl-addons`)를 만들어
`dlopen`으로 물려 쓰는 구조였다.

**SDL은 2.0.14부터 네이티브 AAudio 백엔드(`src/audio/aaudio/`)를 갖고 있고**,
`SDL_audio.c`의 부트스트랩 목록에서 레거시 `ANDROIDAUDIO_bootstrap`보다 **앞에**
등록되어 자동으로 선택된다. 따라서:

- `compat/sdl-addons` 모듈 폐기
- `USE_AAUDIO` 스위치 폐기 (`true`로 두면 빌드가 명시적으로 실패하도록 함)
- 패치가 97줄로 축소 (마우스 warp 억제만 남음)

### 3-B.2 마우스 warp 억제는 여전히 필요

2.32에서 `SDL_WarpMouseInWindow()`는 `SDL_PerformWarpMouseInWindow()`로 위임한다.
SDL의 **Android 비디오 드라이버는 `mouse->WarpMouse`를 구현하지 않으므로**
해당 함수는 `SDL_PrivateSendMouseMotion()`으로 떨어져 **합성 모션 이벤트를 주입**한다.
터치스크린에서 게스트 커서가 튀는 원인이므로 억제를 유지했다.

### 3-B.3 QEMU 11이 이미 고쳐놓은 것

`qemu-5.1.0.patch`에 있던 `ui/sdl2.c`의 NULL console 크래시 가드는 **불필요**하다.
QEMU 11의 `handle_mousemotion()` / `handle_mousebutton()`은 이미
`if (!scon || !qemu_console_is_graphic(scon->dcl.con)) return;` 를 갖고 있다.
`SDL_VIDEODRIVER=x11` 강제 설정 블록도 QEMU 11에는 아예 없다.

### 3-B.4 `monitor/misc.c` 패치는 이식하지 않음

원래 패치는 `monitor_get_fd()`가 `fdname`을 `atoi()`로 해석해 그대로 fd로 쓰게 했다
(주석에도 "FIXME: The lookup for the fd fails below"라고 적혀 있다).
그런데 Limbo의 Java 계층은 `add-fd`/`/dev/fdset/`을 **전혀 쓰지 않고**
`-drive file=/content//<uri>` 형태로 경로를 그대로 넘긴다 — 즉 SAF 처리는 전적으로
`open()` 후킹이 담당한다. 이식하면 이름이 안 맞는 모든 조회가 `atoi()` 쓰레기값을
fd로 반환하는 위험만 남으므로 **의도적으로 제외**했다.

### 3-B.5 `printf` 매크로 vs `-Werror=format-security`

`limbo_logutils.h`는 `printf`/`fprintf`를 logcat으로 보내는 매크로로 치환하는데,
이 헤더가 모든 QEMU 번역 단위에 force-include 되므로 clang의 포맷 문자열 리터럴
분석이 무력화된다. QEMU는 `-Werror`로 빌드하므로 `qemu-io-cmds.c` 등이 깨진다.
→ `-Wno-format-security` 필요 (`QEMU_WARNING_FLAGS`).

### 3-B.6 SDL2 SONAME은 문제없음

§3.1의 SONAME 문제는 SDL2에는 해당하지 않는다. SDL2의 CMake 빌드는
**버전 접미사 없는 `libSDL2.so`** 를 만들기 때문에 그대로 APK에 넣을 수 있다.
그래서 SDL2만 공유 라이브러리로 유지한다 (Java `SDLActivity`와
`compat/sdl-extensions`가 링크해야 하므로 정적화도 불가능하다).

---

## 3-C. SAF 파일 접근: `--wrap` 구현

`objcopy --redefine-sym` 대체는 `compat/limbo_compat_wrap.c`로 구현했다.
링커 플래그는 `LIMBO_WRAP_SYMS`(`android-qemu-config.mak`)에서 생성한다.

구현하면서 **기존 동작의 성능 문제 하나를 같이 고쳤다**: `android_close()`는
호출마다 스레드를 띄우고 JNI로 Java에 들어가 `ParcelFileDescriptor`를 닫는다.
심볼 이름 치환 방식은 대상을 구분할 수 없어 QEMU의 **모든** `close()`(소켓, 파이프,
timerfd, 블록 백엔드 파일 …)가 이 경로를 탔다. 진짜 함수로 가로채면 구분이 가능하므로,
SAF에서 받은 fd만 등록해두고 그것만 비싼 경로로 보낸다.

```c
int __wrap_close(int fd)
{
    if (limbo_saf_fd_take(fd)) {
        return android_close(fd);   /* JNI round trip */
    }
    return close(fd);               /* everything else */
}
```

`__real_*` 별칭은 `--wrap`을 준 링크 안에서만 존재하는데, 이 파일은
`libcompat-limbo.so`(그 링크에 `--wrap` 없음)로 컴파일되므로 파일 안의 `close()`는
이미 libc의 것이다 — 재귀가 생기지 않는다.

`_FORTIFY_SOURCE`가 상수 flags를 가진 `open()`을 `__open_2()`로 재작성하므로
그쪽도 함께 가로챈다.

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

## 5. 상태 요약

| 항목 | 상태 |
|---|---|
| `x86_64-softmmu` arm64-v8a 빌드 (VNC) | **완료** |
| `x86_64-softmmu` arm64-v8a 빌드 (SDL + VNC) | **완료** |
| glib 2.84 / pixman 0.44.2 / libslirp 4.9.1 정적 크로스 빌드 | **완료** |
| SDL2 2.32.4 크로스 빌드 (`libSDL2.so`, AAudio 백엔드 포함) | **완료** |
| `qemu-11.0.3.patch` 무결성 (pristine 트리에 clean apply) | **완료** |
| `sdl2-2.32.4.patch` 무결성 | **완료** |
| `__wrap_*` SAF 후킹 구현 + 실제 리디렉션 검증 | **완료** |
| compat 레이어(`libcompat-limbo.so`) NDK r27 빌드 | **완료** |
| `x86_64` ABI 빌드 | 미실행 (같은 파이프라인, ABI만 교체) |
| JNI 브릿지(`vm-executor-jni.c`) NDK r27 컴파일 | **완료** |
| Java `native` 선언 ↔ 네이티브 구현 대조 | **완료** (§3-E) |
| ndk-build 전체 실행 (`Android.mk` 경유) | 미검증 |
| Gradle APK 조립 | 미검증 |
| 실기기 부팅 테스트 | 미실행 |

`make limbo` 전체 파이프라인과 실기기 검증이 남아 있으므로 **아직 릴리스 가능한 APK는 아니다.**
다만 포팅의 불확실성이 컸던 부분 — QEMU 11을 Android용 공유 라이브러리로 만들 수 있는가,
의존성을 APK에 실을 수 있는가, SDL 프론트엔드를 붙일 수 있는가 — 은 모두 실빌드로 확인됐다.

### 3-D. NDK r27이 드러낸 Limbo 자체 버그

compat 레이어를 NDK r27로 빌드하자 `limbo_compat.c`에서 두 건이 잡혔다.
둘 다 32비트 ABI에서만 돌던 시절의 잔재다.

**`strchrnul()` 셰임이 64비트에서 깨져 있었다.**

```c
int endofs = s + length;   /* 64비트 포인터를 int로 절단 */
return endofs;             /* 절단된 값을 포인터로 반환 */
```

`int`와 포인터 폭이 같은 arm32에서는 우연히 동작했지만 arm64에서는 쓰레기 포인터를
반환한다. QEMU 11은 `util/cutils.c` 등에서 `strchrnul`을 쓰므로 실제로 밟혔을 코드다.
bionic이 API 24부터 `strchrnul`을 제공하므로 **셰임을 삭제**했다.

**`valloc()`이 `<malloc.h>` 없이 `memalign()`을 호출했다.**

암묵적 선언이라 반환값이 `int`로 간주되어 역시 포인터가 절단된다. clang r27은 경고가
아니라 에러로 거부한다. `valloc` 자체는 bionic LP64에 없고 QEMU의
`util/memalign.c:61`이 호출하므로 **셰임은 유지하되 헤더를 추가**했다.

### 3-E. Java ↔ JNI 계약이 깨져 있던 것

네이티브 쪽에서 두 함수를 제거했는데 Java 쪽 스택을 같이 정리하지 않아
런타임 `UnsatisfiedLinkError`가 날 상태였다. Java의 `native` 선언 목록과
실제 구현 심볼을 기계적으로 대조해서 잡았다.

| Java `native` | 왜 구현이 사라졌나 |
|---|---|
| `nativeIgnoreBreakpointInvalidate` | QEMU 11에 `breakpoint_invalidate()`가 없음 |
| `nativeEnableAaudio` | SDL2 AAudio 브리지 패치를 폐기 (§3-B.1) |

두 기능 모두 `res/xml` 설정 화면 → `LimboSettingsManager` → `Activity` →
`Dispatcher` → `MachineAction` → `MachineController` → `MachineExecutor` →
`VMExecutor` → JNI 까지 전체 스택이 살아 있었으므로 전부 제거했다.
`compat/sdl-addons`(AAudio 브리지 모듈)와 `Config.aaudioLibName`도 함께 삭제.

검증 방법 (회귀 방지용으로 재실행 가능):

```sh
# Java가 선언한 native 메서드
grep -rhoE "native [a-zA-Z]+ [a-zA-Z]+\(" VMExecutor.java | sed 's/.* //;s/(//' | sort
# 실제 구현 (JNI + sdl-extensions)
llvm-nm --defined-only vm-executor-jni.o | grep -oE "VMExecutor_[a-zA-Z]+" ...
# 차집합이 비어 있어야 한다
```

### 의도적으로 이식하지 않은 것

| 원래 패치 | 사유 |
|---|---|
| `exec.c` `limbo_ignore_breakpoint_invalidate` | `breakpoint_invalidate()` 자체가 QEMU 11에 없음 |
| `monitor/misc.c` fd 우회 | Limbo가 fdset/getfd를 쓰지 않음 (§3-B.4) |
| `ui/sdl2.c` NULL console 가드 | QEMU 11에 이미 있음 (§3-B.3) |
| `ui/sdl2.c` `SDL_VIDEODRIVER=x11` | QEMU 11에 해당 블록 없음 |
| `SDL_android.c` AAudio 브리지 | SDL 2.0.14+ 네이티브 백엔드로 대체 (§3-B.1) |
| `configure` 기능 탐지 우회 다수 | API 28에서 실제로 제공되므로 강제 비활성이 오히려 해로움 |
| `util/qemu-openpty.c` 스텁 | 파일 자체가 없음 (pty 로직은 `chardev/char-pty.c`) |
| `audio/audio_legacy.c` | 파일 삭제됨 |
