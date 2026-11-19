#!/usr/bin/env bash
#
# libucl/mayhem/test.sh — RUN libucl's own ctest suite (built by mayhem/build.sh in build-tests/) → CTRF.
# PATCH-grade oracle. build.sh compiled the test binaries with normal flags; this only RUNS them.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BUILD=build-tests
[ -d "$BUILD" ] && [ -x "$BUILD/tests/test_basic" ] || { echo "missing $BUILD/tests/test_basic — run mayhem/build.sh first" >&2; exit 2; }

out="$(ctest --test-dir "$BUILD" --output-on-failure 2>&1)"; echo "$out"

# ctest summary line: "<P>% tests passed, <F> tests failed out of <T>"
total=$( printf '%s\n' "$out" | sed -n 's/.*tests passed, [0-9][0-9]* tests failed out of \([0-9][0-9]*\).*/\1/p'  | tail -1)
failed=$(printf '%s\n' "$out" | sed -n 's/.*tests passed, \([0-9][0-9]*\) tests failed out of .*/\1/p'             | tail -1)
: "${total:=0}" "${failed:=0}"
passed=$(( total - failed )); [ "$passed" -lt 0 ] && passed=0

emit_ctrf "cmake-ctest" "$passed" "$failed" 0
