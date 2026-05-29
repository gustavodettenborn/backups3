#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/backup-runtime.conf"
WRAPPER_SCRIPT="$SCRIPT_DIR/backup-wrapper.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

if [ ! -x "$WRAPPER_SCRIPT" ]; then
    echo "Wrapper script not executable: $WRAPPER_SCRIPT" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

if ! [[ "$BACKUP_LOOP_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [ "$BACKUP_LOOP_INTERVAL_SECONDS" -lt 60 ]; then
    echo "Invalid BACKUP_LOOP_INTERVAL_SECONDS: $BACKUP_LOOP_INTERVAL_SECONDS (min 60)" >&2
    exit 1
fi

mkdir -p "$BACKUP_LOG_DIR"

log_line() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$BACKUP_WRAPPER_LOG"
}

TRAY_REF=""

tray_pid_from_ref() {
    local ref="$1"
    if [[ "$ref" == *"|"* ]]; then
        IFS='|' read -r pid _ <<< "$ref"
        echo "$pid"
    else
        echo "$ref"
    fi
}

tray_is_alive() {
    local pid
    pid="$(tray_pid_from_ref "${TRAY_REF:-}")"
    [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

ensure_tray_running() {
    if [ ! -x "$BACKUP_NOTIFIER" ]; then
        return 1
    fi

    if tray_is_alive; then
        return 0
    fi

    TRAY_REF="$($BACKUP_NOTIFIER start-tray "$TRAY_ALWAYS_ON_TEXT" "$BACKUP_ICON_PATH" 2>>"$BACKUP_WRAPPER_LOG" || true)"
    if tray_is_alive; then
        log_line "INFO" "Session tray icon started."
        return 0
    fi

    TRAY_REF=""
    log_line "WARN" "Tray icon not available yet. Will retry automatically."
    return 1
}

cleanup() {
    local ec="$?"
    if [ -n "${TRAY_REF:-}" ] && [ -x "$BACKUP_NOTIFIER" ]; then
        "$BACKUP_NOTIFIER" stop-tray "$TRAY_REF" >/dev/null 2>&1 || true
    fi
    log_line "INFO" "backup-gdrive-daemon stopped with exit code $ec"
    if [ "$ec" -eq 143 ]; then
        exit 0
    fi
    exit "$ec"
}

trap cleanup EXIT INT TERM

log_line "INFO" "backup-gdrive-daemon started. Interval=${BACKUP_LOOP_INTERVAL_SECONDS}s"

ensure_tray_running || true

while true; do
    ensure_tray_running || true
    BACKUP_MANAGED_TRAY=1 "$WRAPPER_SCRIPT"
    status=$?
    log_line "INFO" "backup-gdrive-daemon cycle ended with status=$status. Restarting immediately."
done
