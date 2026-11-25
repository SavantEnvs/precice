#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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

# The oracle: preCICE's own configuration validator (precice-config-validate, built by build.sh with
# the project's normal flags in build/plain) run on known configurations:
#  * upstream's example/integration-test configs must be ACCEPTED (exit 0, "No major issues detected");
#  * mayhem/test-configs/*.xml are invalid configs that must be REJECTED (exit 2) with the exact
#    diagnostic in the matching *.expect file (typo suggestions, unknown data, XML syntax errors);
#  * `precice-tools version` must report the version declared in CMakeLists.txt.
BIN="$SRC/build/plain"
for b in precice-config-validate precice-tools; do
  [ -x "$BIN/$b" ] || { echo "missing $BIN/$b (mayhem/build.sh must build it)" >&2; emit_ctrf precice-config-validate 0 1; exit 1; }
done
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"   # the validator may write scratch output into the cwd
passed=0; failed=0
ok()   { passed=$((passed+1)); echo "PASS $1"; }
bad()  { failed=$((failed+1)); echo "FAIL $1: $2"; }
plain() { sed 's/\x1b\[[0-9;]*m//g' "$1"; }

VALID=(
  examples/solverdummies/precice-config.xml
  tests/serial/mapping-nearest-projection/MappingNearestProjectionEdges.xml
  tests/serial/mapping-nearest-projection/QuadMappingNearestProjectionEdges.xml
)
for c in "${VALID[@]}"; do
  "$BIN/precice-config-validate" "$SRC/$c" > out.txt 2>&1; rc=$?
  if [ "$rc" -eq 0 ] && plain out.txt | grep -qF "No major issues detected"; then ok "$c"; else bad "$c" "rc=$rc"; fi
  # Same config, checked for the participant SolverOne
  "$BIN/precice-config-validate" "$SRC/$c" SolverOne 1 > out.txt 2>&1; rc=$?
  if grep -q '"SolverOne"' "$SRC/$c"; then
    if [ "$rc" -eq 0 ] && plain out.txt | grep -qF "No major issues detected"; then ok "$c (SolverOne)"; else bad "$c (SolverOne)" "rc=$rc"; fi
  fi
done

for x in "$SRC"/mayhem/test-configs/*.xml; do
  exp="${x%.xml}.expect"
  "$BIN/precice-config-validate" "$x" > out.txt 2>&1; rc=$?
  if [ "$rc" -eq 2 ] && plain out.txt | grep -qF "$(cat "$exp")"; then ok "$(basename "$x")"; else bad "$(basename "$x")" "rc=$rc: $(plain out.txt | tail -1)"; fi
done

want="$(sed -n 's/^project(preCICE VERSION \([0-9.]*\).*/\1/p' "$SRC/CMakeLists.txt")"
"$BIN/precice-tools" version > out.txt 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ] && [ -n "$want" ] && grep -q "^${want};" out.txt; then ok "precice-tools version = $want"; else bad "precice-tools version" "rc=$rc want=$want got=$(tail -1 out.txt)"; fi

emit_ctrf precice-config-validate "$passed" "$failed"
