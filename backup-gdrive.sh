#!/bin/bash

# ==============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

# backup-gdrive.sh — Backup do $HOME para Google Drive via rclone
#
# Usa rclone copy (seguro): só envia novos/modificados, NUNCA apaga no Drive.
# Para mover arquivos removidos para uma pasta de segurança, use --backup-dir.
#
# Pré-requisito: configurar um remote do tipo "drive" no rclone:
#   rclone config  →  escolha "drive" e siga as instruções
#
# Uso:
#   ./backup-gdrive.sh                                # executa o backup
#   ./backup-gdrive.sh --dry-run                     # simula sem enviar nada
#   ./backup-gdrive.sh --excluded                    # lista o que NÃO entrará no backup
#   ./backup-gdrive.sh --speed 5M                    # limita a velocidade a 5 MB/s
#   ./backup-gdrive.sh --speed off                   # sem limite de velocidade
#   ./backup-gdrive.sh --speed "08:00,2M 18:00,off" # limite por horário (padrão)
#   ./backup-gdrive.sh --backup-dir deleted          # move removidos para Drive/deleted/ em vez de ignorar
# ==============================================================================

# ── configurações ──────────────────────────────────────────────────────────────
REMOTE="${GDRIVE_REMOTE:-googledrive}"                  # nome do remote configurado no rclone (rclone config)
GDRIVE_FOLDER="${GDRIVE_FOLDER:-backup}"           # pasta raiz no Google Drive
HOSTNAME=$(hostname)
USERNAME=$(whoami)
LOG="${BACKUP_GDRIVE_LOG:-$SCRIPT_DIR/logs/backup-gdrive.log}"
FILTER_FILE="${BACKUP_FILTER_FILE:-$SCRIPT_DIR/backup-filters.txt}"

# Diretórios a fazer backup
SOURCES=(
    "${GDRIVE_SOURCE:-$HOME/}"
)

# ── parse de argumentos ────────────────────────────────────────────────────────
MODE="backup"
BWLIMIT="${GDRIVE_BWLIMIT:-08:00,2M 18:00,off}"   # limite de banda padrão (por horário)
BACKUP_DIR_SUFFIX=""     # pasta no Drive para arquivos removidos (padrão: deleted)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   MODE="dry-run"; shift ;;
        --excluded)  MODE="excluded"; shift ;;
        --speed)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "❌ --speed requer um valor. Ex: --speed 5M ou --speed off"
                exit 1
            fi
            BWLIMIT="$2"; shift 2 ;;
        --backup-dir)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "❌ --backup-dir requer um nome de pasta. Ex: --backup-dir deleted"
                exit 1
            fi
            BACKUP_DIR_SUFFIX="$2"; shift 2 ;;
        --help|-h)
            echo "Uso: $0 [--dry-run | --excluded | --backup-dir <pasta> | --help] [--speed <limite>]"
            echo ""
            echo "  (sem argumento)          Executa o backup (rclone copy — não apaga no Drive)"
            echo "  --dry-run                Simula o backup sem enviar nada"
            echo "  --excluded               Lista os arquivos que NÃO entrarão no backup"
            echo "  --backup-dir <pasta>     Move arquivos removidos para Drive/<pasta>/ em vez de ignorar"
            echo "                           Ex: --backup-dir deleted"
            echo "  --speed <limite>         Define o limite de velocidade para o rclone"
            echo "                           Exemplos: 5M, 10M, off, \"08:00,2M 18:00,off\""
            echo "                           Padrão: \"08:00,2M 18:00,off\""
            exit 0
            ;;
        *)
            echo "❌ Argumento desconhecido: $1"
            echo "   Use --help para ver as opções disponíveis."
            exit 1
            ;;
    esac
done

# ── verifica dependências ──────────────────────────────────────────────────────
if ! command -v rclone &>/dev/null; then
    echo "❌ rclone não encontrado. Instale com: curl https://rclone.org/install.sh | sudo bash"
    exit 1
fi

if [ ! -f "$FILTER_FILE" ]; then
    echo "❌ Arquivo de filtros não encontrado: $FILTER_FILE"
    echo "   Execute o script de setup primeiro."
    exit 1
fi

if ! rclone listremotes | grep -q "^${REMOTE}:"; then
    echo "❌ Remote '${REMOTE}' não encontrado no rclone."
    echo "   Configure com: rclone config"
    echo "   Escolha 'drive' como tipo e siga as instruções de autenticação."
    exit 1
fi

# ── modo: listar excluídos ─────────────────────────────────────────────────────
if [ "$MODE" = "excluded" ]; then
    echo "🔍 Arquivos e diretórios que NÃO entrarão no backup:"
    echo "   Filtros: $FILTER_FILE"
    echo "   Fonte:   ${SOURCES[*]}"
    echo "=============================================="

    for SOURCE in "${SOURCES[@]}"; do
        RELATIVE="${SOURCE#$HOME/}"
        DEST="${REMOTE}:${GDRIVE_FOLDER}/${HOSTNAME}/home/${USERNAME}/${RELATIVE%/}"
        rclone copy "$SOURCE" "$DEST" \
            --filter-from "$FILTER_FILE" \
            --checksum \
            --no-update-modtime \
            --dry-run \
            --log-level DEBUG \
            2>&1 | grep -E "SKIP|Skipping" | sed 's/.*SKIP //;s/.*Skipping //' | sort
    done

    echo ""
    echo "💡 Para ver o tamanho total do que será excluído, rode:"
    echo "   rclone sync \$HOME ${REMOTE}:${GDRIVE_FOLDER}/... --filter-from $FILTER_FILE --dry-run --log-level DEBUG 2>&1 | grep SKIP | wc -l"
    exit 0
fi

# ── modo: dry-run ──────────────────────────────────────────────────────────────
if [ "$MODE" = "dry-run" ]; then
    echo "🔍 DRY-RUN — simulando backup sem enviar nada..."
    echo "   Filtros:    $FILTER_FILE"
    echo "   Velocidade: $BWLIMIT (ignorada no dry-run)"
    echo "============================================="

    for SOURCE in "${SOURCES[@]}"; do
        RELATIVE="${SOURCE#$HOME/}"
        DEST="${REMOTE}:${GDRIVE_FOLDER}/${HOSTNAME}/home/${USERNAME}/${RELATIVE%/}"
        rclone copy "$SOURCE" "$DEST" \
            --filter-from "$FILTER_FILE" \
            --checksum \
            --no-update-modtime \
            --dry-run \
            --log-level NOTICE \
            2>&1
    done

    echo "=============================================="
    echo "✅ Dry-run concluído. Nenhum arquivo foi enviado."
    exit 0
fi

# ── modo: backup real ──────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG")"

echo "======================================" >> "$LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando backup (Google Drive)..." >> "$LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Filtros:    $FILTER_FILE" >> "$LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Velocidade: $BWLIMIT" >> "$LOG"

OVERALL_STATUS=0

for SOURCE in "${SOURCES[@]}"; do
    RELATIVE="${SOURCE#$HOME/}"
    DEST="${REMOTE}:${GDRIVE_FOLDER}/${HOSTNAME}/home/${USERNAME}/${RELATIVE%/}"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copiando: $SOURCE → $DEST" >> "$LOG"

    # Monta flag --backup-dir se solicitado
    BACKUP_DIR_FLAG=()
    if [[ -n "$BACKUP_DIR_SUFFIX" ]]; then
        BACKUP_DEST="${REMOTE}:${GDRIVE_FOLDER}/${BACKUP_DIR_SUFFIX}/${HOSTNAME}/home/${USERNAME}/${RELATIVE%/}"
        BACKUP_DIR_FLAG=(--backup-dir "$BACKUP_DEST")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Arquivos removidos → $BACKUP_DEST" >> "$LOG"
    fi

    # rclone copy só envia arquivos novos ou modificados (nunca sobrescreve idênticos)
    # --checksum: verifica hash SHA256 para detectar mudanças (mais lento, mas seguro)
    # --no-update-modtime: não atualiza metadados se o arquivo for idêntico
    # --ignore-existing: REMOVIDO - queremos atualizar se houver mudanças
    rclone copy "$SOURCE" "$DEST" \
        --filter-from "$FILTER_FILE" \
        --checksum \
        --no-update-modtime \
        --bwlimit "$BWLIMIT" \
        --transfers 4 \
        --checkers 8 \
        --stats 30s \
        --log-level INFO \
        "${BACKUP_DIR_FLAG[@]}" \
        2>&1 | tee -a "$LOG"

    STATUS=${PIPESTATUS[0]}
    if [ $STATUS -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Backup concluído com sucesso." >> "$LOG"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Backup finalizado com erros. Exit code: $STATUS" >> "$LOG"
        OVERALL_STATUS=$STATUS
    fi
done

exit $OVERALL_STATUS
