#!/bin/bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/backup-runtime.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

mkdir -p "$BACKUP_LOG_DIR"

log_line() {
    local level="$1"
    local message="$2"
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
    echo "$line" | tee -a "$BACKUP_WRAPPER_LOG"
}

create_lock() {
    if [ -f "$BACKUP_LOCK_FILE" ]; then
        local lock_pid
        lock_pid="$(cat "$BACKUP_LOCK_FILE" 2>/dev/null || true)"
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" >/dev/null 2>&1; then
            log_line "WARN" "Another backup process is already running with PID $lock_pid"
            return 1
        fi
    fi

    echo "$$" > "$BACKUP_LOCK_FILE"
    return 0
}

cleanup() {
    local exit_code="$1"

    if [ "${BACKUP_MANAGED_TRAY:-0}" != "1" ] && [ -n "${TRAY_PID:-}" ]; then
        "$BACKUP_NOTIFIER" stop-tray "$TRAY_PID" >/dev/null 2>&1 || true
    fi

    rm -f "$BACKUP_LOCK_FILE"
    log_line "INFO" "Wrapper finished with exit code $exit_code"
    exit "$exit_code"
}

if ! create_lock; then
    exit 0
fi

trap 'cleanup $?' EXIT INT TERM

TRAY_PID=""
if [ "${BACKUP_MANAGED_TRAY:-0}" != "1" ] && [ -x "$BACKUP_NOTIFIER" ]; then
    TRAY_PID="$($BACKUP_NOTIFIER start-tray "$TRAY_TEXT" "$BACKUP_ICON_PATH" 2>>"$BACKUP_WRAPPER_LOG" || true)"
    if [ -z "$TRAY_PID" ]; then
        log_line "WARN" "Tray icon not started. Install 'yad' or 'zenity' for persistent tray icon."
    fi
fi

log_line "INFO" "Starting Google Drive backup"

TMP_OUTPUT="$(mktemp "$BACKUP_LOG_DIR/backup-wrapper.XXXXXX")"

if BACKUP_GDRIVE_LOG="$BACKUP_GDRIVE_LOG" "$BACKUP_GDRIVE_SCRIPT" "$@" 2>&1 | tee -a "$BACKUP_WRAPPER_LOG" > "$TMP_OUTPUT"; then
    BACKUP_EXIT=0
else
    BACKUP_EXIT=${PIPESTATUS[0]}
fi

cp "$TMP_OUTPUT" "$BACKUP_LAST_OUTPUT"
rm -f "$TMP_OUTPUT"

if [ "$BACKUP_EXIT" -ne 0 ]; then
    log_line "ERROR" "Google Drive backup exited with status $BACKUP_EXIT"

    if grep -qiE "$AUTH_ERROR_PATTERN" "$BACKUP_LAST_OUTPUT" "$BACKUP_GDRIVE_LOG"; then
        log_line "ERROR" "Authentication error detected"
        if [ -x "$BACKUP_NOTIFIER" ]; then
            "$BACKUP_NOTIFIER" notify-auth \
                "Erro de autenticacao no backup Google Drive" \
                "Reautentique com: rclone config reconnect googledrive:" \
                "$NOTIFY_TIMEOUT_SECONDS" \
                "$BACKUP_ICON_PATH" >/dev/null 2>&1 || true
        fi
    else
        if [ -x "$BACKUP_NOTIFIER" ]; then
            "$BACKUP_NOTIFIER" notify-error \
                "Erro no backup Google Drive" \
                "Falha detectada. Veja logs em $BACKUP_WRAPPER_LOG" \
                "$NOTIFY_TIMEOUT_SECONDS" \
                "$BACKUP_ICON_PATH" >/dev/null 2>&1 || true
        fi
    fi
else
    log_line "INFO" "Google Drive backup finished successfully"
fi

exit "$BACKUP_EXIT"
