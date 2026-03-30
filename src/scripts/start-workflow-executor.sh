#!/bin/bash
# ============================================================
# FlowClaw Workflow Executor — Startup Script
# Launches via Gunicorn (4 workers) for concurrent request handling.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/../logs"
PID_FILE="$LOGS_DIR/workflow-executor.pid"
GUNICORN="$HOME/Library/Python/3.9/bin/gunicorn"

# Fallback: search PATH
if [ ! -x "$GUNICORN" ]; then
    GUNICORN=$(which gunicorn 2>/dev/null || true)
fi

if [ -z "$GUNICORN" ] || [ ! -x "$GUNICORN" ]; then
    echo "ERROR: gunicorn not found. Install with: pip3 install gunicorn --user" >&2
    exit 1
fi

# Ensure logs directory exists
mkdir -p "$LOGS_DIR"

# Load environment from openclaw.json if present (gunicorn doesn't get it automatically)
OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_JSON" ]; then
    export OPENCLAW_CONFIG="$OPENCLAW_JSON"
fi

cd "$SCRIPT_DIR"

echo "Starting FlowClaw Workflow Executor with Gunicorn..."
echo "Workers: 4 | Bind: 0.0.0.0:8765 | Log: $LOGS_DIR/workflow-executor.log"

exec "$GUNICORN" \
    --workers 4 \
    --bind 0.0.0.0:8765 \
    --timeout 600 \
    --graceful-timeout 30 \
    --keep-alive 5 \
    --worker-class sync \
    --log-level info \
    --access-logfile "$LOGS_DIR/workflow-executor.log" \
    --error-logfile "$LOGS_DIR/workflow-executor-error.log" \
    --pid "$PID_FILE" \
    --capture-output \
    workflow-executor:app
