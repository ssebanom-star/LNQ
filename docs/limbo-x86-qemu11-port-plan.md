# Limbo x86 → QEMU 11 포팅 계획서

작성일: 2026-08-01
대상 저장소: [limboemu/limbo](https://github.com/limboemu/limbo) `master` (= `Branch_Branch_6.0.1`, commit `887c6a6`)
목표 QEMU: **11.0.3** (stable, 2026-07-24 릴리스). 11.1.0은 현재 rc2 단계.

---

## 0. 먼저 확인해야 할 전제 (버전 정정)

계획을 세우기 전에 실제 소스를 받아 확인한 결과, **"Limbo가 쓰는 QEMU가 6.0.1"이라는 전제는 사실과 다릅니다.**

| 항목 | 실제 값 | 근거 |
|---|---|---|
| Limbo **앱** 버전 | 6.0.1 (`versionCode 60001`, `versionName "6.0.1-x86"`) | `VERSION` = `600.01`, `limbo-android-x86/src/main/AndroidManifest.xml` |
| 번들된 **QEMU** 버전 | **5.1.0** (기본값) / 2.9.1 (레거시 기기용) | `android-config/android-limbo-config.mak`: `USE_QEMU_VERSION ?= 5.1.0` |
| 존재하는 QEMU 패치 | `qemu-5.1.0.patch`, `qemu-2.9.1.patch` 뿐 | `limbo-android-lib/src/main/jni/patches/` |

즉 `6.0.1`은 Limbo 앱의 자체 버전이고, 실제 포팅 갭은 **QEMU 5.1.0 → 11.0.3** 입니다.
(참고: `limbo-6-native` / `limbo-6-gui` 브랜치에는 `qemu-4.0.0.patch`도 있지만 QEMU 6.x 패치는 어느 브랜치에도 없습니다.)

이 차이는 계획의 난이도를 크게 바꿉니다. QEMU **5.2에서 Makefile 기반 빌드가 Meson으로 완전히 교체**되었기 때문에, 5.1.0에서 출발한다는 것은 Limbo의 네이티브 빌드 파이프라인 전체가 재작성 대상이라는 뜻입니다. 아래 계획은 이 전제로 작성했습니다.

---

## 1. 현행 구조 분석

### 1.1 저장소 레이아웃

```
limbo/
├── build.gradle                 AGP 4.1.1 + jcenter(폐쇄됨)
├── settings.gradle              lib + x86/arm/ppc/sparc 4개 앱 모듈
├── limbo-android-x86/           ← "Limbo x86" (applicationId com.limbo.emu.main)
└── limbo-android-lib/
    ├── src/main/java/...        UI · 머신 관리 · VMExecutor(QEMU 인자 생성)
    ├── src/main/res/raw/        x86_machine_types.txt, x86_cpu.txt 등 목록
    ├── src/main/assets/roms/    pc-bios 복사본
    ├── src/main/jniLibs/<ABI>/  공용 .so
    └── src/main/jni/
        ├── Makefile                     최상위 오케스트레이션 (make limbo)
        ├── Android.mk / Application.mk  ndk-build (compat, SDL2, musl shim)
        ├── android-limbo-build.mak      툴체인/플래그 정의
        ├── android-qemu-build.mak       ★ qemu/Makefile.target 에 주입되는 링크 규칙
        ├── android-config/*.mak         버전별 configure 플래그
        ├── patches/qemu-5.1.0.patch     ★ QEMU Android 호환 패치
        ├── compat/                      bionic 결손 보완 + SAF 파일 접근
        └── limbo/vm-executor-jni.c      ★ dlopen 기반 QEMU 실행기
```

### 1.2 네이티브 빌드 파이프라인 (`make limbo`)

```
ndk-build (compat-musl, compat-limbo, SDL2, sdl-extensions, aaudio, limbo JNI)
  → libffi (autotools)  → glib 2.56.1 (autotools) → pixman 0.40.0 (autotools)
  → qemu ./configure (android-qemu-config.mak가 생성한 거대한 플래그 목록)
  → make -C qemu  ─┬─ Makefile.target 이 android-qemu-build.mak 을 include
                   └─ 표준 링크 규칙을 무력화하고 직접 .so 를 링크
  → libqemu-system-x86_64.so 를 limbo-android-x86/src/main/jniLibs/<ABI>/ 로 복사
  → pc-bios/* 를 assets/roms/ 로 복사
```

핵심은 **QEMU를 실행 파일이 아니라 공유 라이브러리로 만든다**는 점입니다. Android는 앱 전용 디렉터리에서 임의 실행 파일 exec을 막기 때문에(W^X, API 29+), 유일하게 안정적인 방식입니다.

`android-qemu-build.mak`가 하는 일:
1. `$(all-obj-y)`를 `libqemu-system-x86_64.a`로 아카이브
2. `llvm-objcopy --redefine-sym`으로 `open/fopen/close/stat/mkstemp/__open_2`를 Limbo의 SAF 대응 래퍼(`android_*`)로 치환
3. `--whole-archive`로 묶어 `libqemu-system-x86_64.so` 생성

### 1.3 QEMU 패치 표면 (`qemu-5.1.0.patch`, 17개 파일)

| 파일 | 목적 |
|---|---|
| `configure` | pkg-config/SDL/pixman 탐지 우회, `preadv`/`signalfd`/`memfd`/`strchrnul`/`getrandom`/`copy_file_range` 강제 비활성 |
| `Makefile`, `Makefile.target`, `util/Makefile.objs` | 빌드 훅 주입, bridge-helper/tests/drm.o 제외 |
| `include/qemu/osdep.h` | Android `<linux/mman.h>` 포함 |
| `include/ui/console.h`, `ui/console.c` | `GUI_REFRESH_INTERVAL_*`을 매크로 → **전역 변수**로 (JNI에서 런타임 변경) |
| `ui/vnc.c` | `VNC_REFRESH_INTERVAL_*`도 전역 변수화 + Android 키보드 shift 보정 |
| `ui/sdl2.c`, `ui/sdl2-2d.c` | 렌더러 강제(SW/HW), `SDL_HINT_RENDER_SCALE_QUALITY`, NULL console 가드, 해상도 JNI 콜백 |
| `hw/display/vga.c` | `limbo_vga_full_update` 전역 (전체 화면 강제 갱신) |
| `exec.c` | `limbo_ignore_breakpoint_invalidate` 전역 |
| `monitor/misc.c` | `monitor_get_fd`가 fdname을 fd 정수로 직접 해석 |
| `accel/kvm/kvm-all.c` | `%m` 미지원 회피 |
| `audio/audio.c`, `audio/audio_legacy.c` | 기본 샘플레이트 44100 → 22050 |
| `util/qemu-openpty.c` | Android에서 스텁 처리 |

### 1.4 JNI 계약 (`vm-executor-jni.c`)

- `dlopen("libqemu-system-x86_64.so")` 후 `dlsym`으로:
  - 진입점: `qemu_init` → `qemu_main_loop` → `qemu_cleanup` (구버전은 `main`)
  - 종료: `qemu_system_shutdown_request(3)`, `qemu_system_reset_request(6)`
  - 튜닝 전역: `limbo_vga_full_update`, `limbo_ignore_breakpoint_invalidate`, `limbo_sdl_scale_hint`, `gui_refresh_interval_default`, `gui_refresh_interval_idle`, `vnc_refresh_interval_base`, `vnc_refresh_interval_inc`
- 현재 호출: `qemu_main(argc, argv, NULL)`, `qemu_cleanup()` — **QEMU 11 시그니처와 불일치** (§2.6)

---

## 2. QEMU 5.1.0 → 11.0.3 갭 분석

### 2.1 ★ 치명적: 32비트 호스트 지원 완전 삭제 (QEMU 11.0)

> `docs/about/removed-features.rst:575` — "32-bit host operating systems (removed in 11.0) … QEMU dropped all support for all 32-bit host systems."
> `meson.build:327` — `error('QEMU emulator requires a 64-bit CPU host architecture. Only tools may be built for 32-bit.')`

QEMU 11의 `tcg/` 디렉터리에는 64비트 백엔드만 남아 있습니다: `aarch64 loongarch64 mips64 ppc64 riscv64 s390x sparc64 x86_64 tci`. 32비트 `arm`, `i386` 백엔드는 없습니다.

**결론: `armeabi-v7a`와 `x86` ABI는 QEMU 11로 빌드 불가.** (TCI 인터프리터 폴백은 이론상 가능하나 실사용 속도가 아님.)

→ QEMU 11 빌드는 **`arm64-v8a` + `x86_64` 전용**. 32비트 기기는 기존 QEMU 5.1.0/2.9.1 APK를 유지하는 이원화 전략이 필요합니다.
(참고: 64비트 게스트 on 32비트 호스트는 이미 QEMU 10.0에서 차단되었으므로, Limbo의 기본 게스트 `x86_64-softmmu`는 사실상 10.0부터 32비트 기기에서 불가능했습니다.)

### 2.2 ★ 빌드 시스템 전면 교체 (QEMU 5.2 ~ 6.0)

- `Makefile.target` **삭제** → Limbo의 `android-qemu-build.mak` 주입 지점이 사라짐
- `util/Makefile.objs` **삭제** → `*.objs` 체계 자체가 없음
- 빌드는 `configure` → **Meson + Ninja**. `configure`는 이제 Meson 크로스 파일을 생성하는 얇은 래퍼

**대체 전략 (권장):** `meson.build:4449`의 에뮬레이터 타깃 정의를 패치합니다.

```meson
    emulator = executable(exe_name, exe['sources'],
               install: true, c_args: c_args,
               dependencies: arch_deps + exe['dependencies'],
               objects: lib.extract_all_objects(recursive: true),
               link_depends: [block_syms, qemu_syms],
               link_args: link_args, win_subsystem: exe['win_subsystem'])
```

이것을 조건부로 `shared_library(...)`(`name_prefix: 'lib'`, `name_suffix: 'so'`)로 바꾸면 `libqemu-system-x86_64.so`가 곧바로 나옵니다.
유리한 점:
- Linux 경로에서 `emulator_link_args`는 **비어 있고**(`meson.build:824`), 버전 스크립트(`block.syms`/`qemu.syms`)는 `--enable-modules`일 때만 적용 → 심볼 가시성 제약 없음
- `lib.extract_all_objects(recursive: true)`가 이미 전체 오브젝트를 모아주므로 `--whole-archive` 수작업 불필요
- `system/main.c`의 `main()`이 .so 안에 남아도 무해 (dlopen 시 무시)

**`objcopy --redefine-sym` 대체:** Meson/Ninja 파이프라인에는 중간 `.a` 재가공 훅이 없습니다. 대신 링커의 `--wrap`을 씁니다.

```
-Wl,--wrap=open -Wl,--wrap=fopen -Wl,--wrap=close -Wl,--wrap=stat -Wl,--wrap=mkstemp -Wl,--wrap=__open_2
```

`compat/`에 `__wrap_open()` 등을 구현하고 필요 시 `__real_open()`으로 위임합니다. objcopy 방식보다 견고하고, 정적 아카이브를 재작성하지 않아도 됩니다.

### 2.3 ★ 의존성 최소 버전 상향

| 의존성 | Limbo 현재 | QEMU 11 요구 | 조치 |
|---|---|---|---|
| **glib** | 2.56.1 (autotools) | **≥ 2.66** (`meson.build:1050`) | 2.78~2.84로 교체. glib 2.58+는 **Meson 전용 빌드**이므로 기존 autotools 레시피 폐기 |
| meson | 없음 | **≥ 1.5.0** (Rust 사용 시 ≥1.10) | 호스트에 설치. QEMU 11 tarball은 `python/wheels/`에 meson 1.10.0 동봉 |
| python | — | **≥ 3.9** | 호스트 요구사항 |
| ninja | — | 필수 | 호스트 요구사항 |
| **zlib** | 암묵적 | `dependency('zlib', required: true)` (`meson.build:1152`) | NDK sysroot의 `libz` 사용 + `.pc` 파일 제공 |
| pixman | 0.40.0 | ≥ 0.21.8, VNC/GTK/SPICE 활성 시 **필수** | 0.42+ 로 갱신 (Meson 빌드) |
| SDL2 | 2.0.8 | `dependency('sdl2')` | 2.28.5 이상(권장 2.32.x)로 갱신 — 최신 NDK 대응 |
| libffi | 3.3 | glib 의존 | 3.4.x |
| **slirp** | QEMU 내장 정적 lib | **외부 `libslirp` (pkg-config)** 또는 `subprojects/slirp.wrap` 다운로드 | libslirp 4.8+ 를 NDK로 별도 크로스 빌드 (사용자 모드 네트워킹 = Limbo 기본 `-net user` 이므로 필수) |
| **libfdt** | `qemu/dtc/libfdt` 내장 | 시스템 libfdt(≥1.5.1) 또는 `subprojects/dtc.wrap` **네트워크 다운로드** | dtc를 오프라인 벤더링. 단, x86_64-softmmu 전용이면 `--disable-fdt` 가능 |
| rustc | — | 선택 (≥1.83) | **비활성** (`--disable-rust`) |

`subprojects/packagecache/`에는 Rust crate만 들어 있고 dtc/slirp tarball은 없습니다 → 오프라인 빌드를 위해 직접 벤더링이 필요합니다.

### 2.4 ★ 소스 파일 이동/삭제 — 기존 패치 재작성 필요

| Limbo가 패치한 파일 | QEMU 11 상태 |
|---|---|
| `exec.c` | **삭제** → `system/physmem.c` 등으로 분해. `breakpoint_invalidate()` 자체가 **없음** → `limbo_ignore_breakpoint_invalidate` 훅 **폐기** |
| `Makefile.target` | **삭제** → `meson.build` |
| `util/Makefile.objs` | **삭제** → `util/meson.build` |
| `monitor/misc.c` | **삭제** → `monitor_get_fd()`는 `monitor/fds.c:142` |
| `audio/audio_legacy.c` | **삭제** → `audio/audio.c:253`만 패치 |
| `util/qemu-openpty.c` | **삭제** → pty 로직은 `chardev/char-pty.c` |
| `configure` | 존재하나 내용 완전히 다름 — 기존 hunk 전부 무효 |
| `include/ui/console.h`, `ui/console.c`, `ui/vnc.c`, `ui/sdl2.c`, `ui/sdl2-2d.c`, `hw/display/vga.c`, `accel/kvm/kvm-all.c`, `include/qemu/osdep.h`, `audio/audio.c` | **존재** — 훅 위치 재조정 후 재적용 가능 |

`GUI_REFRESH_INTERVAL_DEFAULT`(`include/ui/console.h:47`), `VNC_REFRESH_INTERVAL_BASE/INC`(`ui/vnc.c:59-60`)는 그대로 있어 전역 변수화 패치는 동일 방식으로 이식 가능합니다.

`configure` 우회 hunk의 상당수는 **이제 불필요**합니다. Meson 크로스 파일에 `[properties]`와 `[binaries] pkg-config`를 제대로 지정하면 탐지가 정상 동작하고, `signalfd`/`memfd`/`getrandom`/`strchrnul` 같은 항목은 최신 NDK(API 24~28 이상)에서 실제로 제공되므로 강제 비활성이 오히려 해롭습니다. 각 항목을 개별 재평가해야 합니다.

### 2.5 ★ 삭제된 CLI 옵션 — Limbo가 실제로 쓰는 것들

`VMExecutor.java`가 생성하는 인자 중 QEMU 11에서 **제거된** 것:

| 옵션 | 제거 버전 | Limbo 위치 | 대체 |
|---|---|---|---|
| `-tb-size` | 6.0 | `VMExecutor.java:286` | `-accel tcg,tb-size=N` |
| `-realtime mlock=` | 6.0 | `VMExecutor.java:291` | `-overcommit mem-lock=on|off` |
| `-soundhw` | 7.1 | `VMExecutor.java:251` | `-device sb16` / `-device AC97` / `-device ES1370` / `-device intel-hda` + `-device hda-duplex` / `-device adlib` / `-device cs4231a` / `-device gus` / `-device isa-pcspk` |
| `-no-acpi` | 9.0 | `VMExecutor.java:339` | `-machine acpi=off` |
| `-no-hpet` | 9.0 | `VMExecutor.java:342` | `-machine hpet=off` |

유지되는 옵션(확인 완료): `-vga -sd -hda/-hdb/-hdc/-hdd -cdrom -fda/-fdb -drive -device -net -m -smp -cpu -M -boot -k -usb -serial -parallel -monitor -qmp -vnc -kernel -initrd -append -rtc -incoming -nographic -nodefaults -overcommit -accel -enable-kvm`

### 2.6 ★ 진입점 API 시그니처 변경

| 심볼 | QEMU 5.1 (Limbo 가정) | QEMU 11 |
|---|---|---|
| `qemu_init` | `void qemu_init(int, char**, char**)` | `void qemu_init(int argc, char **argv)` — `include/system/system.h:108` |
| `qemu_main_loop` | `void ()` | `int qemu_main_loop(void)` — `include/system/system.h:109` |
| `qemu_cleanup` | `void ()` | `void qemu_cleanup(int status)` — `include/system/system.h:110` |
| `qemu_system_shutdown_request` | 동일 | `void (ShutdownCause)` — 유지 |
| `qemu_system_reset_request` | 동일 | `void (ShutdownCause)` — 유지 |

또한 QEMU 11의 `system/main.c`는 BQL/replay mutex를 `qemu_init` 이후 해제하고 별도 스레드에서 `qemu_default_main`을 도는 구조입니다. JNI 실행기가 `main()`을 직접 호출하지 않고 세 함수를 순차 호출한다면 **락 소유권 처리**를 그대로 흉내내야 합니다 (`bql_unlock()` / `replay_mutex_unlock()`).
→ 더 안전한 대안: `.so`에 남아 있는 `main()` 심볼을 그대로 `dlsym`해서 호출하고, 종료는 기존대로 `qemu_system_shutdown_request()`로 처리.

### 2.7 머신 타입 / 장치 목록 노후화

`res/raw/x86_machine_types.txt`에 있는 49개 항목 중 **QEMU 11에 존재하는 것은 소수**입니다.
QEMU 11의 i440fx/q35 머신은 **4.1 이상만** 정의되어 있습니다 (`hw/i386/pc_piix.c`, `hw/i386/pc_q35.c`: `DEFINE_I440FX_MACHINE(4,1)` ~ `DEFINE_I440FX_MACHINE_AS_LATEST(11,0)`).

- **삭제됨**: `pc-1.0` ~ `pc-1.3`, `pc-i440fx-1.4` ~ `pc-i440fx-4.0`, `pc-q35-2.4` ~ `pc-q35-4.0.1`
- **유지**: `pc`, `q35`, `isapc`, `microvm`, `none`, `pc-i440fx-4.1`+, `pc-q35-4.1`+

`x86_cpu.txt`의 CPU 모델은 확인한 범위에서 모두 QEMU 11에 존재합니다 (`486 athlon Conroe kvm32 qemu32 n270 pentium3 KnightsMill` 등 전부 `target/i386/cpu.c`에 있음). 다만 신규 모델(`Icelake-Server`, `SapphireRapids`, `EPYC-Genoa`, `GraniteRapids` 등)이 빠져 있으니 갱신 권장.

`common_soundcards.txt`(`sb16 ac97 adlib cs4231a gus es1370 hda pcspk all`)는 `-soundhw` 제거에 맞춰 `-device` 이름으로 재매핑해야 합니다 (`all` 항목은 폐기).

### 2.8 pc-bios 자산 변화

QEMU 11 `pc-bios/`는 79개 항목. Limbo의 `COPY_ROMS` 규칙(`*.rom *.bin *.img *.bmp *.ico *.svg *.rsrc openbios-* README`)은 다음을 놓칩니다:

- `edk2-*.fd.bz2` (UEFI 펌웨어, **압축 상태로 배포** — 빌드 시 `meson`이 압축 해제)
- `descriptors/` (firmware JSON)
- `dtb/` (device tree blobs)
- `*.aml` (ACPI 테이블)

x86_64 전용이라면 최소 필요 세트는 `bios-256k.bin`, `vgabios*.bin`, `efi-*.rom`, `kvmvapic.bin`, `linuxboot_dma.bin`, `multiboot_dma.bin`, `keymaps/`, (UEFI 부팅 지원 시) `edk2-x86_64-code.fd` + `edk2-i386-vars.fd`.

### 2.9 Android 앱 레이어 노후화

| 항목 | 현재 | 필요 |
|---|---|---|
| Gradle Plugin | 4.1.1 | 8.x |
| Gradle | 7.0.2 | 8.7+ |
| 저장소 | **`jcenter()`** (2021 폐쇄) | `mavenCentral()` |
| compileSdk / targetSdk | 29 / 29 | 35~36 (Play 정책) |
| minSdk | 21 | 23+ 권장 |
| NDK | r14b(gcc) / r23b(clang) | r27 / r28 (clang 전용, gcc 경로 삭제) |
| abiFilters | 4개 ABI | **`arm64-v8a`, `x86_64`만** (§2.1) |
| 16 KB 페이지 | 미대응 | `-Wl,-z,max-page-size=16384` (Android 15+ 필수) |
| `com.android.support:multidex` | 레거시 | `androidx.multidex` |

---

## 3. 아키텍처 결정

### 안 A (권장): 기존 `.so` + `dlopen` 구조 유지, Meson에 shared_library 패치

- 장점: Limbo의 UI/JNI/SDL 통합, SAF 파일 접근, 런타임 튜닝 전역 변수 등 자산을 전부 보존. 앱 하나로 완결.
- 단점: QEMU 업스트림 패치를 계속 유지보수해야 함 (다만 패치량은 ~10줄 수준으로 작음).

### 안 B: Termux/Alpine prefix에서 실행 파일로 구동 (Vectras 방식)

[Vectras VM](https://github.com/xoureldeen/Vectras-VM-Android)은 이미 QEMU 11.0.0을 Android에서 돌리고 있는데, 방식이 다릅니다 — `apk`(Alpine/musl) prefix를 기기에 풀고 그 안에서 **표준 QEMU 실행 파일**을 돌리며 화면은 termux-x11(`libXlorie.so`)로 띄웁니다 (`qemu/11.0.0/build.sh` 참조).

- 장점: QEMU 패치 거의 불필요, 업스트림 추종 쉬움
- 단점: 수백 MB 부트스트랩 배포, Limbo의 SDL 직결 UI/SAF 통합 폐기, 앱 구조 전면 재작성. **Limbo 포팅이 아니라 다른 앱을 만드는 일에 가까움**

→ **안 A로 진행**. 단, 안 B는 32비트 기기 및 GPU(3dfx/virgl) 확장 시 참고 자산으로 유지.

---

## 4. 단계별 실행 계획

### Phase 0 — 기준선 확보 (1주)

- [ ] `limboemu/limbo` 포크, `qemu-11` 작업 브랜치 생성
- [ ] Ubuntu 22.04/24.04 + NDK r23b 환경에서 **현행 QEMU 5.1.0 빌드를 그대로 재현** (arm64-v8a / x86_64-softmmu)
  - 재현 실패 시 QEMU 11 실패와 구분이 불가능해지므로 반드시 선행
- [ ] 실기기 또는 Android 에뮬레이터(arm64)에서 게스트 부팅 확인 → 회귀 판정 기준선
- [ ] `scripts/fetch-sources.sh` 로 소스 취득 자동화 (본 저장소에 포함)

**산출물**: 재현 가능한 기준선 APK + 빌드 로그

### Phase 1 — 툴체인 및 의존성 현대화 (2~3주)

- [ ] NDK r27/r28 고정, gcc 경로(`USE_GCC`, `GCC_TOOLCHAIN_VERSION=4.9`, `android-armv7a-softfp.mak`) 제거
- [ ] `BUILD_HOST` 유효값을 `arm64-v8a`, `x86_64`로 축소하고 32비트 지정 시 명시적 에러 출력
- [ ] **Meson 크로스 파일 생성기** 작성 (`android-config/meson-cross-<abi>.ini.in`)
  ```ini
  [binaries]
  c          = '<NDK>/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android23-clang'
  ar         = '<NDK>/.../llvm-ar'
  strip      = '<NDK>/.../llvm-strip'
  pkg-config = 'pkg-config'
  [host_machine]
  system = 'android'   # 또는 'linux' — QEMU configure는 __linux__ 로 판별하므로 둘 다 검증
  cpu_family = 'aarch64'
  cpu = 'aarch64'
  endian = 'little'
  ```
- [ ] **가짜 pkg-config sysroot** 구축 (`$PKG_CONFIG_LIBDIR`) — `glib-2.0.pc gmodule-no-export-2.0.pc gio-2.0.pc gthread-2.0.pc pixman-1.pc zlib.pc sdl2.pc slirp.pc libfdt.pc`
- [ ] 의존성 크로스 빌드 레시피 재작성:
  - libffi 3.4.x (autotools 유지 가능)
  - **glib 2.78+ (Meson)** — bionic에는 `libintl`/`iconv`가 없으므로 기존 `compat/musl`, `compat-intl`, `compat-iconv` 자산을 glib Meson 빌드에 연결. `libpcre2` 필요
  - pixman 0.42+ (Meson)
  - SDL2 2.32.x + Limbo의 `sdl2-2.0.8.patch` 이식 + `sdl-extensions`/`sdl-addons`(AAudio) 갱신
  - **libslirp 4.8+** 신규 (Meson)
  - dtc/libfdt 벤더링 (또는 `--disable-fdt`)
- [ ] `-Wl,-z,max-page-size=16384` 전 링크 단계 적용

**리스크**: glib on bionic이 이 단계 최대 난관. 실패 시 폴백은 [Termux glib 패치셋](https://github.com/termux/termux-packages) 참조.

**산출물**: `obj/local/<ABI>/` 에 갱신된 의존성 `.so`/`.a` + 유효한 `.pc` 세트

### Phase 2 — QEMU 11 빌드 부트스트랩 (2~3주)

- [ ] QEMU 11.0.3 tarball 취득, `qemu/` 배치
- [ ] `android-qemu-config-11.0.3.mak` 신규 작성 — configure 플래그 재정리:
  ```
  --target-list=x86_64-softmmu --cross-prefix=... --cc=...
  --enable-sdl --enable-vnc --enable-slirp --enable-kvm
  --disable-rust --disable-docs --disable-tools --disable-guest-agent
  --disable-gtk --disable-curses --disable-opengl --disable-vte
  --disable-gnutls --disable-nettle --disable-gcrypt
  --disable-seccomp --disable-libudev --disable-user
  --audio-drv-list=sdl --with-coroutine=sigaltstack
  --disable-fdt          # x86_64 전용 시
  ```
  (`--disable-blobs`, `--disable-zlib-test`, `--with-sdlabi`, `--disable-capstone`, `--disable-malloc-trim`, `--enable-coroutine-pool` 등 5.1 시절 플래그는 **모두 삭제됨** → 전수 재검증 필요)
- [ ] `android-qemu-config.mak`의 버전 분기에 `11.0.3` 추가, `USE_QEMUSTAB`/`USE_SLIRP_LIB`/`USE_SDL_ABI` 같은 구버전 스위치 정리
- [ ] **`meson.build` 패치**: `executable()` → `shared_library()` (§2.2)
  - 새 옵션 `-Dlimbo_shared_emulator=true`를 `meson_options.txt`에 추가하여 조건부 처리
- [ ] `Makefile`의 `_qemu` / `_build-qemu` 타깃을 `ninja -C build`로 교체, `android-qemu-build.mak` 폐기
- [ ] `--wrap` 기반 SAF 후킹으로 `objcopy --redefine-sym` 대체 + `compat/limbo_compat_filesystem.c`에 `__wrap_*` 구현
- [ ] `COPY_ROMS` 규칙을 QEMU 11 `pc-bios/` 레이아웃에 맞게 갱신 (§2.8)

**검증 기준**: `libqemu-system-x86_64.so`가 생성되고 `llvm-nm -D`에 `qemu_init`, `qemu_main_loop`, `qemu_cleanup`, `qemu_system_shutdown_request`가 노출될 것

### Phase 3 — Android 호환 패치 재작성 (2주)

- [ ] `patches/qemu-11.0.3.patch` 신규 작성
  - `include/qemu/osdep.h` — `<linux/mman.h>` (여전히 필요한지 재확인)
  - `include/ui/console.h` + `ui/console.c` — `gui_refresh_interval_default/idle` 전역화
  - `ui/vnc.c` — `vnc_refresh_interval_base/inc` 전역화 + Android 키보드 shift 보정 (`key_event`)
  - `ui/sdl2.c` — 렌더러 강제, `limbo_sdl_scale_hint`, NULL console 가드 (QEMU 11 코드에 이미 `SDL_HINT_RENDER_DRIVER`/`RENDER_BATCHING` 설정이 있으므로 충돌 확인)
  - `ui/sdl2-2d.c` — `Android_JNI_SetVMResolution` 콜백
  - `hw/display/vga.c` — `limbo_vga_full_update`
  - `accel/kvm/kvm-all.c` — `%m` 회피
  - `audio/audio.c` — 기본 22050 Hz (`audio/audio.c:253`)
  - `monitor/fds.c` — `monitor_get_fd` fd 직접 해석 (Limbo가 SAF fd를 넘기는 경로)
  - **폐기**: `exec.c` 훅(대상 함수 소멸), `Makefile*`/`Makefile.objs` 훅, `configure` 훅 대부분, `qemu-openpty.c` 훅
- [ ] `diff -ru` 대신 **git 기반 패치**(`git format-patch`)로 전환 — 유지보수성 향상

### Phase 4 — JNI/런타임 계약 갱신 (1주)

- [ ] `vm-executor-jni.c` 진입점 수정:
  - `qemu_init(argc, argv)` (2인자, `void` 반환)
  - `int qemu_main_loop(void)` 반환값 수신
  - `qemu_cleanup(status)` 인자 전달
  - 또는 `.so`의 `main()` 심볼 직접 호출 방식으로 단순화 (BQL/replay mutex 처리 회피 — §2.6)
- [ ] `limbo_ignore_breakpoint_invalidate` 관련 JNI 메서드 및 Java UI 옵션 제거 (`VMExecutor.nativeIgnoreBreakpointInvalidate`)
- [ ] 나머지 전역 튜닝 심볼 `dlsym` 동작 확인

### Phase 5 — Java/UI 레이어 마이그레이션 (2주)

- [ ] `VMExecutor.java` 인자 생성 로직 수정 (§2.5 매핑표대로)
  - `-soundhw X` → `-device <매핑>`
  - `-tb-size N` → `-accel tcg,tb-size=N` (기존 `-accel` 인자와 병합 로직 필요)
  - `-realtime mlock=` → `-overcommit mem-lock=`
  - `-no-acpi` / `-no-hpet` → `-machine acpi=off` / `-machine hpet=off` (기존 `-M` 인자와 병합)
- [ ] `res/raw/x86_machine_types.txt` 를 QEMU 11 목록으로 교체
- [ ] `res/raw/x86_cpu.txt` 갱신 (신규 모델 추가)
- [ ] `res/raw/common_soundcards.txt` 를 `-device` 이름 기반으로 교체
- [ ] 기존 사용자 머신 설정 **마이그레이션 루틴** 추가 — 삭제된 머신 타입(`pc-i440fx-2.x` 등)을 저장한 VM은 그대로 두면 부팅 실패. DB 업그레이드 시 `pc`로 폴백 + 안내
- [ ] `assets/QEMU_VERSION` 갱신, CHANGELOG 작성

### Phase 6 — Gradle/앱 현대화 (1주)

- [ ] AGP 8.x / Gradle 8.7+ / `mavenCentral()`
- [ ] `compileSdk 36`, `targetSdk 35`, `minSdk 23`
- [ ] `abiFilters "arm64-v8a", "x86_64"`
- [ ] `androidx.multidex` 전환, deprecated 의존성(`lifecycle-extensions` 등) 정리
- [ ] `namespace` 속성 이관 (AGP 8 필수), manifest `package` 제거

### Phase 7 — 검증 및 릴리스 (2주)

- [ ] 부팅 매트릭스: DOS(FreeDOS) / Windows 98 / Windows XP / Debian(콘솔) / Alpine / Android-x86
- [ ] UI 매트릭스: SDL 전체화면·회전·일시정지/재개, VNC 접속, 키보드/마우스(절대좌표 포함)
- [ ] 저장소 매트릭스: SAF(`content://`) 이미지, 내부 저장소, hda/hdb/cdrom/fd, 스냅샷/`-incoming`
- [ ] 사운드: sb16 / AC97 / intel-hda
- [ ] 네트워크: `-net user` (slirp) 포워딩
- [ ] 성능 회귀 측정 vs QEMU 5.1.0 기준선 (부팅 시간, 화면 갱신 FPS)
- [ ] 32비트 기기용 레거시 APK 유지 전략 확정 및 스토어 문구 정리

---

## 5. 리스크 및 완화

| # | 리스크 | 영향 | 완화 |
|---|---|---|---|
| R1 | **32비트 기기 지원 상실** | 사용자 기반 상당수 이탈 | 32비트는 QEMU 5.1.0 레거시 APK로 분리 유지. 스토어에 명시 |
| R2 | **glib 2.78+ NDK 크로스 빌드 실패** | Phase 1 정체 | Termux 패치셋 참조. 최악의 경우 glib 2.66 (요구 최소치)로 하향 |
| R3 | Meson `shared_library` 패치가 업스트림 변경에 취약 | 릴리스마다 재작업 | 패치를 10줄 이내로 최소화. QEMU 마이너 업글마다 CI로 검증 |
| R4 | 성능 회귀 (5.1.0 대비 QEMU 11이 무거움) | 체감 저하 | `-Ofast` 유지, `--disable-debug-info`, TCG 튜닝(`tb-size`) 노출. 기준선과 정량 비교 |
| R5 | KVM은 사실상 사용 불가 (대부분 기기가 `/dev/kvm` 미노출) | 없음(기존과 동일) | 옵션 유지, 실패 시 TCG 폴백 메시지 |
| R6 | SDL2 2.32 + QEMU 11 `ui/sdl2.c`의 힌트 설정 충돌 | 화면 깨짐 | Phase 3에서 힌트 우선순위 명시적 정리 |
| R7 | `--wrap` 후킹이 QEMU 내부 `qemu_open_internal` 경로를 못 잡음 | SAF 파일 접근 실패 | `util/osdep.c`의 `qemu_open_internal`을 직접 패치하는 방식 병행 |
| R8 | 사용자 기존 VM 설정이 삭제된 머신 타입 참조 | 업데이트 후 부팅 실패 | Phase 5 마이그레이션 루틴 + 실패 시 안내 다이얼로그 |
| R9 | 라이선스: QEMU/glib/SDL2 GPL·LGPL 준수 | 배포 이슈 | 패치 및 빌드 스크립트 공개 유지 (Limbo는 GPLv2) |

---

## 6. 일정 요약

| Phase | 내용 | 기간 |
|---|---|---|
| 0 | 기준선 확보 | 1주 |
| 1 | 툴체인·의존성 현대화 | 2~3주 |
| 2 | QEMU 11 빌드 부트스트랩 | 2~3주 |
| 3 | Android 호환 패치 재작성 | 2주 |
| 4 | JNI 계약 갱신 | 1주 |
| 5 | Java/UI 마이그레이션 | 2주 |
| 6 | Gradle/앱 현대화 | 1주 |
| 7 | 검증·릴리스 | 2주 |
| | **합계** | **13~15주** (1인 기준) |

Phase 1과 Phase 5/6은 병렬 진행 가능 → 2인 투입 시 9~11주.

---

## 7. 결정이 필요한 항목

1. **32비트 기기 처리**: 레거시 APK 이원 유지 vs 지원 중단
2. **게스트 아키텍처 범위**: `x86_64-softmmu`만 vs `aarch64`/`ppc64`/`sparc64` 동시 포팅
   (본 계획은 x86 우선. 다른 게스트는 `--disable-fdt` 불가 → dtc 벤더링 필수)
3. **UEFI 지원**: `edk2-x86_64-code.fd` 번들 여부 (APK 용량 +4MB 내외)
4. **업스트림 기여**: `shared_library` 패치를 QEMU 업스트림에 제안할지 여부 (장기 유지보수 비용 대폭 감소)
5. **QEMU 버전 고정**: 11.0.3(stable) vs 11.1.0 정식 릴리스 대기

---

## 부록 A. 검증에 사용한 근거

| 주장 | 확인 위치 (qemu-11.0.3) |
|---|---|
| 32비트 호스트 삭제 | `docs/about/removed-features.rst:575`, `meson.build:327`, `tcg/` 디렉터리 목록 |
| meson ≥ 1.5.0 | `meson.build:1` |
| glib ≥ 2.66 | `meson.build:1050` |
| zlib 필수 | `meson.build:1152` |
| pixman ≥ 0.21.8 | `meson.build:1148` |
| slirp = pkg-config 외부 의존 | `meson.build:1271-1274`, `subprojects/slirp.wrap` |
| fdt = 시스템 또는 dtc subproject | `meson.build:2067-2093`, `subprojects/dtc.wrap` |
| rustc ≥ 1.83 (선택) | `meson.build:101` |
| coroutine `sigaltstack` 사용 가능 | `meson.build:511` |
| 에뮬레이터 링크 타깃 | `meson.build:4449` |
| `emulator_link_args` 비어 있음 (Linux) | `meson.build:824` |
| 진입점 시그니처 | `include/system/system.h:108-110` |
| 종료 API | `include/system/runstate.h:131,141` |
| `-soundhw` 제거(7.1) | `docs/about/removed-features.rst:399` |
| `-no-acpi` 제거(9.0) | `docs/about/removed-features.rst:469` |
| `-no-hpet` 제거(9.0) | `docs/about/removed-features.rst:463` |
| `-realtime` 제거(6.0) | `docs/about/removed-features.rst:227` |
| `-tb-size` 제거(6.0) | `docs/about/removed-features.rst:239` |
| i440fx 머신 4.1+ 만 존재 | `hw/i386/pc_piix.c:396-436` |
| `pc-bios/` 79개 항목 | `ls pc-bios | wc -l` |

| 주장 | 확인 위치 (limbo @ 887c6a6) |
|---|---|
| 번들 QEMU = 5.1.0 | `limbo-android-lib/src/main/jni/android-config/android-limbo-config.mak` |
| 앱 버전 6.0.1 | `VERSION`, `limbo-android-x86/src/main/AndroidManifest.xml` |
| Makefile.target 훅 | `patches/qemu-5.1.0.patch` (Makefile.target hunk) |
| objcopy 심볼 치환 | `jni/android-qemu-build.mak` |
| dlopen 진입점 | `jni/limbo/vm-executor-jni.c` |
| 제거된 CLI 옵션 사용 | `.../jni/VMExecutor.java:251,286,291,339,342` |
| jcenter / AGP 4.1.1 | `build.gradle` |

## 부록 B. 참고 프로젝트

- [Vectras VM](https://github.com/xoureldeen/Vectras-VM-Android) — Alpine prefix + termux-x11 방식으로 **이미 QEMU 11.0.0을 Android에서 구동 중**. `qemu/11.0.0/build.sh`에 의존성 목록이 있어 Phase 1 참조용으로 유용
- [Termux packages](https://github.com/termux/termux-packages) — glib/pixman/SDL2의 Android(bionic) 패치셋
