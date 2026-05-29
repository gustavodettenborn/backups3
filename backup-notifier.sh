#!/bin/bash

set -u

command_name="${1:-}"
shift || true

log_fallback() {
    local message="$1"
    if command -v logger >/dev/null 2>&1; then
        logger -t backup-gdrive "$message"
    fi
}

notify_auth_error() {
    local title="$1"
    local body="$2"
    local timeout_ms="$3"
    local icon_path="$4"

    local sent=1

    local notify_icon="dialog-warning"
    if [ -n "$icon_path" ] && [ -f "$icon_path" ]; then
        notify_icon="$icon_path"
    fi

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -t "$timeout_ms" -a "backup-gdrive" -i "$notify_icon" "$title" "$body" && sent=0
    fi

    if [ "$sent" -ne 0 ] && command -v kdialog >/dev/null 2>&1; then
        kdialog --title "$title" --passivepopup "$body" "$((timeout_ms / 1000))" && sent=0
    fi

    if [ "$sent" -ne 0 ] && command -v zenity >/dev/null 2>&1; then
        zenity --notification --text "$title: $body" >/dev/null 2>&1 && sent=0
    fi

    if [ "$sent" -ne 0 ]; then
        log_fallback "$title - $body"
    fi
}

notify_generic_error() {
    local title="$1"
    local body="$2"
    local timeout_ms="$3"
    local icon_path="$4"

    local sent=1

    local notify_icon="dialog-error"
    if [ -n "$icon_path" ] && [ -f "$icon_path" ]; then
        notify_icon="$icon_path"
    fi

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u normal -t "$timeout_ms" -a "backup-gdrive" -i "$notify_icon" "$title" "$body" && sent=0
    fi

    if [ "$sent" -ne 0 ] && command -v kdialog >/dev/null 2>&1; then
        kdialog --title "$title" --passivepopup "$body" "$((timeout_ms / 1000))" && sent=0
    fi

    if [ "$sent" -ne 0 ] && command -v zenity >/dev/null 2>&1; then
        zenity --notification --text "$title: $body" >/dev/null 2>&1 && sent=0
    fi

    if [ "$sent" -ne 0 ]; then
        log_fallback "$title - $body"
    fi
}

start_tray_icon() {
    local text="$1"
    local icon_path="$2"

    local tray_icon="folder-sync"
    if [ -n "$icon_path" ] && [ -f "$icon_path" ]; then
        tray_icon="$icon_path"
    fi

    if command -v yad >/dev/null 2>&1; then
        yad --notification --image="$tray_icon" --text="$text" --command="true" >/dev/null 2>&1 &
        local yad_pid
        yad_pid="$!"
        sleep 1
        if kill -0 "$yad_pid" >/dev/null 2>&1; then
            echo "$yad_pid"
            return 0
        fi
    fi

    if command -v zenity >/dev/null 2>&1; then
        local fifo
        local zenity_pid
        local keep_writer_pid

        fifo="/tmp/backup-tray-${USER:-user}-$$-${RANDOM}.fifo"
        rm -f "$fifo"
        if ! mkfifo "$fifo"; then
            echo "Failed to create tray fifo: $fifo" >&2
            return 1
        fi

        zenity --notification --listen <"$fifo" >/dev/null 2>&1 &
        zenity_pid="$!"

        # Keep FIFO open to prevent zenity from exiting after first command.
        tail -f /dev/null >"$fifo" 2>/dev/null &
        keep_writer_pid="$!"

        printf 'icon:%s\ntooltip:%s\n' "$tray_icon" "$text" >"$fifo"
        sleep 1
        if ! kill -0 "$zenity_pid" >/dev/null 2>&1; then
            kill "$keep_writer_pid" >/dev/null 2>&1 || true
            rm -f "$fifo"
            echo "zenity tray process exited during startup" >&2
            return 1
        fi
        echo "${zenity_pid}|${keep_writer_pid}|${fifo}"
        return 0
    fi

    echo "Persistent tray icon unavailable: install yad or zenity package" >&2
    return 1
}

stop_tray_icon() {
    local tray_ref="$1"
    local tray_pid=""
    local keep_writer_pid=""
    local fifo=""

    if [[ "$tray_ref" == *"|"* ]]; then
        IFS='|' read -r tray_pid keep_writer_pid fifo <<< "$tray_ref"
    else
        tray_pid="$tray_ref"
    fi

    if [ -n "$tray_pid" ] && kill -0 "$tray_pid" >/dev/null 2>&1; then
        kill "$tray_pid" >/dev/null 2>&1 || true
    fi

    if [ -n "$keep_writer_pid" ] && kill -0 "$keep_writer_pid" >/dev/null 2>&1; then
        kill "$keep_writer_pid" >/dev/null 2>&1 || true
    fi

    if [ -n "$fifo" ] && [ -p "$fifo" ]; then
        rm -f "$fifo"
    fi
}

case "$command_name" in
    notify-auth)
        title="${1:-Erro de autenticacao no backup}"
        body="${2:-Reautentique o remote do Google Drive com rclone config reconnect googledrive:}"
        timeout_seconds="${3:-12}"
        icon_path="${4:-}"
        timeout_ms="$((timeout_seconds * 1000))"
        notify_auth_error "$title" "$body" "$timeout_ms" "$icon_path"
        ;;
    notify-error)
        title="${1:-Erro no backup Google Drive}"
        body="${2:-Falha detectada. Verifique logs para detalhes.}"
        timeout_seconds="${3:-12}"
        icon_path="${4:-}"
        timeout_ms="$((timeout_seconds * 1000))"
        notify_generic_error "$title" "$body" "$timeout_ms" "$icon_path"
        ;;
    start-tray)
        text="${1:-Backup em execucao}"
        icon_path="${2:-}"
        start_tray_icon "$text" "$icon_path"
        ;;
    stop-tray)
        stop_tray_icon "${1:-}"
        ;;
    *)
        echo "Uso: $0 {notify-auth|notify-error|start-tray|stop-tray}"
        exit 1
        ;;
esac
