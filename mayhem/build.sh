#!/usr/bin/env bash
# libucl/mayhem/build.sh — cmake build (ASan+UBSan) + the ucl_add_string_fuzzer libFuzzer harness,
# its standalone reproducer, and libucl's own ctest suite (normal flags) so mayhem/test.sh only RUNS it.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}" ; : "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS

# Two UBSan checks fire on every input before the parser does anything interesting, and
# -fno-sanitize-recover makes each one an abort, so with them on this target can only ever report them:
#   * mum.h's hash reads uint32/uint64 at unaligned offsets ON PURPOSE (_MUM_UNALIGNED_ACCESS is 1 on
#     x86) -> "load of misaligned address" for every key or macro name hashed;
#   * ucl_hash_destroy() calls its ucl_hash_free_func through a void(*)(void*) -> "call through pointer
#     to incorrect function type" for every object freed.
# Relax exactly these two checks; ASan and the rest of UBSan stay on and halting.
UBSAN_RELAX="-fno-sanitize=alignment,function"
[ -n "${SANITIZER_FLAGS}" ] || UBSAN_RELAX=""
cd "$SRC"

# 1) Build libucl as a static lib WITH the sanitizers so the fuzzed code is instrumented.
cmake -S . -B build -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $UBSAN_RELAX" -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $UBSAN_RELAX"
cmake --build build -j"$MAYHEM_JOBS" --target ucl

LIBUCL="$(find "$SRC/build" -name 'libucl.a' | head -1)"
HARNESS="$SRC/tests/fuzzers/ucl_add_string_fuzzer.c"
INCS="-I$SRC/include -I$SRC/src"

# 2) The libFuzzer binary (the Mayhem target) and a standalone (non-fuzzer) run-once reproducer.
#    Both respect $SANITIZER_FLAGS (empty off-switch -> clean variants). This harness is C, so the
#    standalone driver links directly (no need to compile it as a separate C object first).
#    mayhem/lsan_off.cc turns LeakSanitizer off at build time (ASan/UBSan stay on): libucl's own fuzz
#    harness never frees the parser, so LSan would report a leak on nearly every input.
$CXX $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$SRC/lsan_off.o"
$CC $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$HARNESS" $INCS "$LIBUCL" "$SRC/lsan_off.o" -o /mayhem/ucl_add_string_fuzzer
$CC $SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" "$HARNESS" $INCS "$LIBUCL" "$SRC/lsan_off.o" -o /mayhem/ucl_add_string_fuzzer-standalone

# 3) Build libucl's own ctest suite with NORMAL flags (a clean, separate build) so mayhem/test.sh
#    only RUNS it. ENABLE_TESTING()/ADD_SUBDIRECTORY(tests) is on by default in the top CMakeLists.
env -u CFLAGS -u CXXFLAGS -u LDFLAGS \
    cmake -S . -B build-tests -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build-tests -j"$MAYHEM_JOBS"
