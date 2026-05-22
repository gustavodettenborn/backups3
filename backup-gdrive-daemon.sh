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

cleanup() {
    local ec="$?"
    if [ -n "${TRAY_REF:-}" ] && [ -x "$BACKUP_NOTIFIER" ]; then
        "$BACKUP_NOTIFIER" stop-tray "$TRAY_REF" >/dev/null 2>&1 || true
    fi
    log_line "INFO" "backup-gdrive-daemon stopped with exit code $ec"
    exit "$ec"
}

trap cleanup EXIT INT TERM

log_line "INFO" "backup-gdrive-daemon started. Interval=${BACKUP_LOOP_INTERVAL_SECONDS}s"

if [ -x "$BACKUP_NOTIFIER" ]; then
    TRAY_REF="$($BACKUP_NOTIFIER start-tray "$TRAY_ALWAYS_ON_TEXT" "$BACKUP_ICON_PATH" 2>>"$BACKUP_WRAPPER_LOG" || true)"
    if [ -z "$TRAY_REF" ]; then
        log_line "WARN" "Tray icon not started (install/use yad or zenity)."
    else
        log_line "INFO" "Session tray icon started."
    fi
fi

while true; do
    BACKUP_MANAGED_TRAY=1 "$WRAPPER_SCRIPT"
    status=$?
    log_line "INFO" "backup-gdrive-daemon cycle ended with status=$status"
    sleep "$BACKUP_LOOP_INTERVAL_SECONDS"
done
