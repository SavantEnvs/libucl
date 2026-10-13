#!/usr/bin/env bash
# libucl/mayhem/build.sh (mining layer) — cmake build (ASan+UBSan) + the ucl_msgpack_fuzzer libFuzzer harness,
# its standalone reproducer, and libucl's own ctest suite (normal flags) so mayhem/test.sh only RUNS it.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}" ; : "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS
cd "$SRC"

# 1) Build libucl as a static lib WITH the sanitizers so the fuzzed code is instrumented.
cmake -S . -B build -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS" -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS"
cmake --build build -j"$MAYHEM_JOBS" --target ucl

LIBUCL="$(find "$SRC/build" -name 'libucl.a' | head -1)"
HARNESS="$SRC/tests/fuzzers/ucl_msgpack_fuzzer.c"
INCS="-I$SRC/include -I$SRC/src -I$SRC/uthash"

# 2) The libFuzzer binary (the Mayhem target) and a standalone (non-fuzzer) run-once reproducer.
#    Both respect $SANITIZER_FLAGS (empty off-switch -> clean variants). This harness is C, so the
#    standalone driver links directly (no need to compile it as a separate C object first).
#    The harness leaks its parser objects by design; mayhem/lsan_off.cc turns LeakSanitizer off at build time.
$CXX $SANITIZER_FLAGS -c mayhem/lsan_off.cc -o /tmp/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$HARNESS" $INCS "$LIBUCL" /tmp/lsan_off.o -o /mayhem/ucl_msgpack_fuzzer
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" "$HARNESS" $INCS "$LIBUCL" /tmp/lsan_off.o -o /mayhem/ucl_msgpack_fuzzer-standalone

# 3) Build libucl's own ctest suite with NORMAL flags (a clean, separate build) so mayhem/test.sh
#    only RUNS it. ENABLE_TESTING()/ADD_SUBDIRECTORY(tests) is on by default in the top CMakeLists.
env -u CFLAGS -u CXXFLAGS -u LDFLAGS \
    cmake -S . -B build-tests -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX"
cmake --build build-tests -j"$MAYHEM_JOBS"
