#!/usr/bin/env bash
#
# Verifies that the Java layer and the native libraries still agree.
#
# Two contracts are easy to break when native code is added or removed, and
# neither the Java compiler nor the linker can see the mismatch -- it only
# shows up as a crash on the device:
#
#   1. System.loadLibrary("X") needs a libX.so packaged in the APK.
#      Getting this wrong kills the app the moment the activity starts,
#      with an UnsatisfiedLinkError naming the missing library.
#
#   2. Every "native" method declared in Java needs a matching
#      Java_<class>_<method> symbol. Getting this wrong kills the app the
#      first time that specific method is called, which may be much later.
#
# Both have already happened once during the QEMU 11 port: dropping
# compat/musl and the AAudio bridge left loadLibrary calls and native
# declarations pointing at code that no longer existed.
#
# Usage:  check-jni-contract.sh <ABI> <NDK_ROOT>
#
set -uo pipefail

ABI="${1:?ABI required}"
NDK_ROOT="${2:?NDK_ROOT required}"

HERE="$(cd "$(dirname "$0")" && pwd)"
JNI="$(cd "$HERE/.." && pwd)"
MAIN="$(cd "$JNI/.." && pwd)"
PRJ="$(cd "$MAIN/../../.." && pwd)"

JAVA_SRC="$MAIN/java"
NM="$NDK_ROOT/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64/bin/llvm-nm"

# Every directory an APK could pick native libraries up from.
LIB_DIRS=("$MAIN/jniLibs/$ABI")
for m in "$PRJ"/limbo-android-*/src/main/jniLibs/"$ABI"; do
    [ -d "$m" ] && LIB_DIRS+=("$m")
done

fail=0
note() { printf '  %s\n' "$*"; }

######################################################################
# 1. System.loadLibrary("X")  ->  libX.so must be packaged
#
# LimboSDLActivity deliberately overrides SDLActivity.loadLibraries() with an
# empty body, so SDL's own {"SDL2", "main"} list never runs and libmain.so is
# not required. Only look at explicit loadLibrary calls.
######################################################################
echo "checking System.loadLibrary() against packaged libraries ($ABI)"

mapfile -t wanted < <(grep -rhoE 'System\.loadLibrary\("[^"]+"\)' "$JAVA_SRC" \
    | sed 's/.*("//;s/")//' | sort -u)

for lib in "${wanted[@]}"; do
    found=""
    for d in "${LIB_DIRS[@]}"; do
        [ -f "$d/lib$lib.so" ] && found="$d/lib$lib.so" && break
    done
    if [ -n "$found" ]; then
        note "OK   lib$lib.so"
    else
        note "FAIL lib$lib.so -- loaded by Java, not present in any jniLibs/$ABI"
        fail=1
    fi
done

# loadQEMULib() picks the emulator library by guest at run time and relies on
# catching the failure of the ones that are not built, so those names are
# deliberately not checked here.

######################################################################
# 2. Java "native" methods  ->  JNI symbols must exist
######################################################################
echo "checking Java native declarations against JNI exports"

if [ ! -x "$NM" ]; then
    note "SKIP llvm-nm not found at $NM"
else
    # Declared: strip the return type and the argument list.
    # Note the character class must not contain an escaped bracket -- inside
    # [...] a "]" ends the class no matter how it is written, which silently
    # made an earlier version of this pattern match nothing at all.
    mapfile -t declared < <(grep -rhoE 'native +[A-Za-z_][A-Za-z0-9_]*(\[\])? +[A-Za-z_][A-Za-z0-9_]* *\(' "$JAVA_SRC" \
        | sed -E 's/.* ([A-Za-z_][A-Za-z0-9_]*) *\($/\1/' | sort -u)

    if [ "${#declared[@]}" -eq 0 ]; then
        note "FAIL found no native declarations at all -- the pattern is broken"
        fail=1
    fi

    # Implemented: any Java_..._<name> symbol in the packaged libraries.
    implemented=$(for d in "${LIB_DIRS[@]}"; do
        [ -d "$d" ] && "$NM" -D --defined-only "$d"/*.so 2>/dev/null
    done | grep -oE 'Java_[A-Za-z0-9_]+' | sed -E 's/.*_([A-Za-z0-9]+)$/\1/' | sort -u)

    for m in "${declared[@]}"; do
        if grep -qx "$m" <<< "$implemented"; then
            note "OK   $m"
        else
            note "FAIL $m -- declared native in Java, no JNI symbol found"
            fail=1
        fi
    done
fi

echo
if [ "$fail" -ne 0 ]; then
    echo "JNI contract check FAILED: the app would crash on device." >&2
    exit 1
fi
echo "JNI contract OK"
