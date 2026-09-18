# Checklist de limpeza manual no Google Drive

Estes diretórios/arquivos já foram enviados ao Drive em backups anteriores, mas
**a partir de agora não serão mais sincronizados** (novos filtros em
`backup-filters.txt` + `--ignore-case` em `backup-gdrive.sh`). Como o backup
usa `rclone copy` (nunca apaga nada no Drive), eles continuam ocupando espaço
lá até serem removidos manualmente pelo navegador.

Prefixo base no Drive: `backup/invisible/home/gustavodettenborn/`
(remote `googledrive:`, conforme `GDRIVE_FOLDER`/hostname/usuário configurados em `.env`)

Marque conforme for apagando:

## Caches de apps Electron (bug de case-sensitivity corrigido)
- [ ] `.config/Claude/Cache`
- [ ] `.config/Claude/Code Cache`
- [ ] `.config/Claude/GPUCache`
- [ ] `.config/Claude/DawnWebGPUCache`
- [ ] `.config/Claude/DawnGraphiteCache`
  (~230 MB no total)
- [ ] `.config/Kiro/Cache`
- [ ] `.config/Kiro/CachedData`
- [ ] `.config/Kiro/CachedExtensionVSIXs`
- [ ] `.config/Kiro/CachedProfilesData`
- [ ] `.config/Kiro/GPUCache`
- [ ] `.config/Kiro/DawnWebGPUCache`
- [ ] `.config/Kiro/DawnGraphiteCache`
  (~160 MB no total)
- [ ] `.config/Cursor/Cache`
- [ ] `.config/Cursor/CachedData`
- [ ] `.config/Cursor/CachedExtensionVSIXs`
- [ ] `.config/Cursor/CachedProfilesData`
- [ ] `.config/Cursor/GPUCache`
- [ ] `.config/Cursor/DawnWebGPUCache`
- [ ] `.config/Cursor/DawnGraphiteCache`
  (~12 MB no total)

## Auto-update / extensões reinstaláveis
- [ ] `.local/share/claude/versions` (~8.5 GB — maior item, priorize este)
- [ ] `.local/share/GitKrakenCLI/versions` (~213 MB)
- [ ] `.kiro/extensions` (~207 MB)
- [ ] `.eclipse` (~71 MB)

## Instaladores em Downloads
- [ ] `Downloads/google-chrome-stable_current_amd64.deb`
- [ ] `Downloads/google-chrome-stable_current_amd64 (1).deb`
  (outros `*.deb`/`*.AppImage` que existirem em `Downloads/`, se houver)

---

**Espaço total estimado a recuperar: ~9,2 GB** (a maior parte é o item
`.local/share/claude/versions`).
