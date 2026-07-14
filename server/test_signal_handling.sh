#!/bin/bash
# 信号审计与配置校验精确终止测试：不得用全局 pkill 误杀正式服务。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/hy2.sh"

FAIL=0
TEST_ROOT=$(mktemp -d)
export HIHY_ROOT_DIR="$TEST_ROOT"
trap 'jobs -pr | xargs -r kill 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; FAIL=1; }

sleep 30 &
validation_pid=$!
HIHY_VALIDATION_PID=$validation_pid
stopValidationProcess

if ! kill -0 "$validation_pid" 2>/dev/null; then
    pass "validation process is stopped by exact PID"
else
    fail "validation process is still running"
fi

audit_log="$TEST_ROOT/logs/signal-audit.log"
if grep -q "signal=TERM target_pid=${validation_pid} .*reason=config-validation" "$audit_log"; then
    pass "validation signal contains PID and reason audit data"
else
    fail "validation signal audit entry missing"
fi

sleep 30 &
service_pid=$!
pid_file="$TEST_ROOT/hihy.pid"
printf '%s\n' "$service_pid" >"$pid_file"
killHysteriaProcess TERM "$pid_file" "test-service-stop"

if ! kill -0 "$service_pid" 2>/dev/null; then
    pass "service PID-file process is stopped"
else
    fail "service PID-file process is still running"
fi

if grep -q "signal=TERM target_pid=${service_pid} .*reason=test-service-stop:pid-file" "$audit_log"; then
    pass "service stop signal records its call reason"
else
    fail "service stop audit entry missing"
fi

if grep -A15 '^stopValidationProcess()' "$SCRIPT_DIR/src/45-wizard.sh" \
    | grep -Ev '^[[:space:]]*#' \
    | grep -qE '(^|[[:space:]])pkill[[:space:]]'; then
    fail "validation cleanup still contains broad pkill"
else
    pass "validation cleanup has no broad pkill"
fi

if grep -q 'reason=service-script:openrc-stop' "$SCRIPT_DIR/src/55-service.sh" \
    && grep -q 'reason=service-script:rc-stop' "$SCRIPT_DIR/src/55-service.sh"; then
    pass "generated service stop paths contain signal audit markers"
else
    fail "generated service stop signal audit markers missing"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "ALL signal_handling TESTS PASSED"
else
    exit 1
fi
