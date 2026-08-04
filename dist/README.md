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

## Status

**Build 2.** Build 1 failed the moment you pressed Start -- the app itself came
up fine.

`setupNativeLibs()` still called `System.loadLibrary()` for `compat-musl`,
`glib-2.0` and `pixman-1`. None of them exist any more: glib and pixman are
statically linked into `libqemu-system-x86_64.so`, and compat-musl was dropped
because bionic provides iconv from API 28. Any one of them throws
`UnsatisfiedLinkError`.

That code runs from the Start handler, not at startup, because
`Config.loadNativeLibsEarly` is false and `loadNativeLibsMainThread` is true:

```java
mStart.setOnClickListener(new OnClickListener() {
    public void onClick(View view) {
        if (!Config.loadNativeLibsEarly && Config.loadNativeLibsMainThread) {
            setupNativeLibs();          // <- throws here
        }
```

It sits ahead of any decision about the display backend, which is why **VNC and
SDL failed identically**. `libLoaded` is only set at the end of the method, so
every Start press re-ran the same failing load.

`make install` now runs `android-config/check-jni-contract.sh`, which fails the
build if a `loadLibrary` name has no packaged `.so`, or a Java `native`
declaration has no JNI symbol. Neither the compiler nor the linker can see
those mismatches.

### If SDL still fails but VNC works

Limbo's bundled SDL Java glue (`org/libsdl/app/*.java`) is from the SDL 2.0.8
era while the native library is now SDL 2.32.4. SDL's C code looks its Java
callbacks up with `GetStaticMethodID`, and 23 of the methods it asks for are
missing from the bundled glue -- `initTouch`, `setRelativeMouseEnabled`,
`supportsRelativeMouse`, `requestPermission`, `getAudioOutputDevices`,
`hapticStop` and others.

That contract is only exercised once the SDL activity starts, so it should not
affect the VNC path. Fixing it means replacing the four bundled Java files with
SDL 2.32.4's nine and re-applying Limbo's customisations on top. Not done yet.

## Please read before installing

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
