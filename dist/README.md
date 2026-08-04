# limbo-x86-qemu11-7.0.0-arm64-v8a-debug.apk

Limbo x86 with QEMU **11.0.3** (upstream Limbo 6.0.1 ships QEMU 5.1.0).

| | |
|---|---|
| package | `com.limbo.emu.main` |
| version | 7.0.0-x86 (versionCode 70000) |
| ABI | **arm64-v8a only** |
| minSdk / targetSdk | 28 (Android 9) / 35 |
| size | ~41 MB |
| signing | Gradle **debug** keystore |
| sha256 | see `sha256sum` output below |

Contents:

```
lib/arm64-v8a/libqemu-system-x86_64.so   34 MB, QEMU 11.0.3, SDL + VNC + slirp
lib/arm64-v8a/libSDL2.so                 SDL 2.32.4
lib/arm64-v8a/libcompat-limbo.so         SAF file hooks (__wrap_*)
lib/arm64-v8a/libcompat-SDL2-ext.so      input/screen extensions
lib/arm64-v8a/liblimbo.so                JNI bridge
assets/roms/                             117 firmware files (BIOS, VGA BIOS,
                                         option ROMs, edk2 UEFI, keymaps)
```

## Versioning

`limbo/VERSION` is the single source of truth; `build.gradle` derives both
`versionName` and `versionCode` from it. Bump the patch component by 0.0.1 for
every build handed out, so a reported problem always maps to an exact APK.

| version | what changed | outcome |
|---|---|---|
| 7.0.0 | first build | Start button died: `loadLibrary` of compat-musl / glib-2.0 / pixman-1, all removed |
| 7.0.1 | that fix, plus `-net ...,vlan=0` removed (gone from QEMU since 3.0) | still dies -- cause unknown |

## Status: 7.0.1 still fails, and I need a log

Both VNC and SDL still die when a VM starts. Everything ruled out so far was
found by reading code, and that has run out of road -- QEMU calls `exit()` on a
fatal option or a missing file, and inside a `dlopen`ed library that takes the
whole process down with no Java exception and no dialog. The reason is printed
first, and it goes to logcat.

**The catch: the logcat tag is not "limbo".** `limbo_logutils.h` builds the tag
from `__FILE__ ":" __LINE__`, so QEMU's messages appear under tags like
`vl.c:1234` or `qemu-error.c:56`. Filtering on "limbo" or "qemu" hides exactly
the lines that matter.

```sh
adb logcat -c && adb logcat > limbo.log
# start the VM in another window, then Ctrl-C once it dies
```

An unfiltered dump is what is needed. The first `error_report` line before the
process disappears should name the problem outright.

## Please read before installing## Please read before installing

**This build has never been run.** No emulator on this machine could execute
arm64 Android, so nothing here has booted a guest, drawn a frame, or opened a
disk image. What has been verified is static: every library links, exports the
symbols the Java layer looks up, carries only unversioned dependencies, and is
16 KB page aligned. That is enough to say it *should* load; it is not evidence
that it runs.

Treat it as a smoke test. The most informative thing you can do is install it,
start a VM, and capture logcat:

```sh
adb install -r limbo-x86-qemu11-7.0.0-arm64-v8a-debug.apk
adb logcat -c && adb logcat | tee limbo.log
```

Things most likely to go wrong first, in order:

1. `dlopen` of `libqemu-system-x86_64.so` failing — would show as an
   `UnsatisfiedLinkError` or a linker message in logcat.
2. SDL surface/renderer setup on your device's GPU.
3. Pointer behaviour — `compat/sdl-extensions` calls SDL internals, which
   needed a build workaround (see `docs/qemu11-build-results.md` §3-B).
4. Disk images opened through the Storage Access Framework: the interception
   moved from `objcopy --redefine-sym` to linker `--wrap` and has not been
   exercised at run time.

## Known behaviour changes vs Limbo 6.0.1

- 32-bit devices are unsupported (QEMU 11 removed all 32-bit hosts).
- Machine types older than `pc-i440fx-4.1` / `pc-q35-4.1` no longer exist.
  A saved VM pointing at one will fail to start; pick a current machine type.
- The "Ignore Breakpoint Invalidation" and "Enable Aaudio" settings are gone.
  Audio now goes through SDL's native AAudio backend automatically.
- The `all` sound-card option is gone (`-soundhw` was removed in QEMU 7.1).

Build provenance and the full list of issues found along the way:
`../docs/qemu11-build-results.md`.
4ffab84cb183c2f3ca11b3d4dc60bac4cee0c669513928b742cd7c615be48f92  dist/limbo-x86-qemu11-7.0.0-arm64-v8a-debug.apk
