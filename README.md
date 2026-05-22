# backups3 - Backup Google Drive

Este projeto executa backup do diretorio HOME para Google Drive usando rclone, com foco em:

- execucao continua em segundo plano desde o inicio da sessao (systemd --user)
- deteccao de erro de autenticacao
- notificacao para o usuario logado
- icone persistente na bandeja durante toda a sessao (estilo daemon)

## Inicio rapido (5 minutos)

Comando unico de instalacao:

```bash
./install.sh
```

Instalacao manual (alternativa):

1. Instale dependencias:

```bash
sudo apt update
sudo apt install rclone libnotify-bin kde-cli-tools zenity yad
```

2. Crie seu arquivo de ambiente local:

```bash
cp .env.example .env
```

Edite `.env` com os valores desejados (paths, remotes, limites, icone, intervalo).

3. Configure o remote Google Drive no rclone:

```bash
rclone config
rclone listremotes | grep '^googledrive:'
```

4. Ative o modo continuo na sessao:

```bash
mkdir -p ~/.config/systemd/user
cp systemd/user/backup-gdrive.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user disable --now backup-gdrive.timer 2>/dev/null || true
systemctl --user enable --now backup-gdrive.service
```

5. Rode uma execucao manual inicial:

```bash
systemctl --user start backup-gdrive.service
systemctl --user status backup-gdrive.service
```

## Publicacao no GitHub

- `.env` esta no `.gitignore` (nao sera versionado)
- use `.env.example` como template publico de configuracao
- logs/locks locais tambem estao no `.gitignore`

## Escopo

Este README cobre apenas o fluxo Google Drive:

- `backup-gdrive.sh`
- `backup-wrapper.sh`
- `backup-notifier.sh`
- `backup-runtime.conf`
- `systemd/user/backup-gdrive.service`
- `systemd/user/backup-gdrive.timer`

## Estrutura

```text
backups3/
├── backup-gdrive.sh
├── backup-wrapper.sh
├── backup-notifier.sh
├── backup-runtime.conf
├── backup-filters.txt
├── logs/
└── systemd/user/
    ├── backup-gdrive.service
    └── backup-gdrive.timer
```

## Como funciona

1. O service user inicia automaticamente no login da sessao.
2. O service executa `backup-gdrive-daemon.sh` continuamente.
3. O daemon roda `backup-wrapper.sh` em ciclos.
4. O wrapper cria lockfile para evitar concorrencia.
5. O daemon inicia um unico icone persistente de bandeja na sessao.
6. O wrapper chama `backup-gdrive.sh` e captura saida/exit code.
7. Se houver erro, o wrapper procura padroes de autenticacao no log/saida.
8. Em erro de autenticacao, o wrapper chama `backup-notifier.sh`.
9. O wrapper remove apenas lockfile e finaliza o ciclo.
10. O daemon aguarda o intervalo configurado e inicia novo ciclo mantendo o mesmo icone.

## Dependencias

Obrigatorias:

- `rclone`
- `systemd --user`

Para notificacao/icone:

- `notify-send` (libnotify-bin)
- `kdialog` (kde-cli-tools)
- `zenity` (fallback para notificacao)
- `yad` (obrigatorio para icone de bandeja persistente)

Instalacao recomendada no Kubuntu:

```bash
sudo apt update
sudo apt install rclone libnotify-bin kde-cli-tools zenity yad
```

## Configuracao rclone (Google Drive)

Se ainda nao existir remote `googledrive`:

```bash
rclone config
```

Depois valide:

```bash
rclone listremotes | grep '^googledrive:'
```

## Uso manual

Backup normal:

```bash
./backup-gdrive.sh
```

Simulacao sem envio:

```bash
./backup-gdrive.sh --dry-run
```

Listar excluidos por filtro:

```bash
./backup-gdrive.sh --excluded
```

Limite de velocidade:

```bash
./backup-gdrive.sh --speed 5M
./backup-gdrive.sh --speed off
```

## Execucao em segundo plano (systemd user)

Copiar unidades para systemd do usuario:

```bash
mkdir -p ~/.config/systemd/user
cp systemd/user/backup-gdrive.service ~/.config/systemd/user/
cp systemd/user/backup-gdrive.timer ~/.config/systemd/user/
```

Ativar modo continuo na sessao:

```bash
systemctl --user daemon-reload
systemctl --user disable --now backup-gdrive.timer 2>/dev/null || true
systemctl --user enable --now backup-gdrive.service
```

Executar/reiniciar imediatamente (opcional):

```bash
systemctl --user start backup-gdrive.service
```

Ver status:

```bash
systemctl --user status backup-gdrive.service
systemctl --user status backup-gdrive.timer
```

Intervalo entre ciclos (padrao 21600 segundos = 6 horas):

```bash
sed -i 's/^BACKUP_LOOP_INTERVAL_SECONDS=.*/BACKUP_LOOP_INTERVAL_SECONDS="3600"/' backup-runtime.conf
systemctl --user restart backup-gdrive.service
```

## Logs e arquivos de estado

Diretorio padrao: `logs/`

Arquivos principais:

- `logs/backup-gdrive.log` -> log do rclone
- `logs/backup-wrapper.log` -> log do orquestrador
- `logs/backup-last-output.log` -> ultima saida capturada
- `logs/backup-gdrive.lock` -> lock de execucao

Acompanhar logs:

```bash
tail -f logs/backup-wrapper.log
tail -f logs/backup-gdrive.log
journalctl --user -u backup-gdrive.service -f
```

## Deteccao de erro de autenticacao

O wrapper detecta erro de autenticacao por regex configurada em `backup-runtime.conf`, incluindo termos como:

- `invalid_grant`
- `Failed to refresh token`
- `Token has been revoked`
- `401`
- `403`
- `Invalid Credentials`

Quando detectado:

1. registra `Authentication error detected` no log
2. envia notificacao para usuario logado
3. mensagem recomendada: `rclone config reconnect googledrive:`
4. em outros erros (nao-auth), envia alerta normal de erro na bandeja do SO

## Notificacoes e icone da bandeja

`backup-notifier.sh` usa fallback em cadeia:

1. `notify-send`
2. `kdialog`
3. `zenity`
4. `logger`

Para icone de bandeja constante na sessao:

- o daemon inicia uma vez e mantem o icone ativo durante toda a sessao
- usa `yad --notification` quando disponivel
- se o `yad` falhar/encerrar cedo, usa fallback persistente com `zenity --notification --listen`
- icone padrao: `images/backup.png`

Se nao houver suporte grafico no contexto de execucao, o backup continua e cai para log.

## Teste controlado de erro de autenticacao

Use este teste para validar o alerta sem alterar token real:

```bash
printf '#!/bin/bash\necho "ERROR: Failed to refresh token: invalid_grant"\necho "ERROR: googleapi: Error 401: Invalid Credentials"\nexit 1\n' > /tmp/mock-gdrive-auth-fail.sh
chmod +x /tmp/mock-gdrive-auth-fail.sh
env BACKUP_GDRIVE_SCRIPT=/tmp/mock-gdrive-auth-fail.sh ./backup-wrapper.sh
rm -f /tmp/mock-gdrive-auth-fail.sh
```

Resultado esperado:

1. retorno de erro no wrapper
2. linha `Authentication error detected` em `logs/backup-wrapper.log`
3. notificacao no desktop para o usuario logado

## Arquivo de configuracao

`backup-runtime.conf` controla:

- caminhos (`BACKUP_HOME`, `BACKUP_LOG_DIR`)
- lock/logs (`BACKUP_LOCK_FILE`, `BACKUP_WRAPPER_LOG`, `BACKUP_GDRIVE_LOG`)
- script alvo (`BACKUP_GDRIVE_SCRIPT`)
- regex de autenticacao (`AUTH_ERROR_PATTERN`)
- timeout de notificacao (`NOTIFY_TIMEOUT_SECONDS`)
- texto do icone (`TRAY_TEXT`)
- caminho do icone (`BACKUP_ICON_PATH`)

O projeto carrega configuracoes de `.env` automaticamente em:

- `backup-runtime.conf`
- `backup-gdrive.sh`
- `backup-s3.sh`

## Troubleshooting rapido

Remote nao encontrado:

```bash
rclone listremotes
rclone config
```

Reautenticar Google Drive:

```bash
rclone config reconnect googledrive:
```

Ver ultima falha de service:

```bash
journalctl --user -u backup-gdrive.service -n 100 --no-pager
```

Verificar comandos disponiveis no PATH:

```bash
for c in rclone notify-send kdialog yad zenity; do command -v "$c" || echo "faltando: $c"; done
```

Checklist rapido de saude:

```bash
systemctl --user is-enabled backup-gdrive.service
systemctl --user is-active backup-gdrive.service
systemctl --user --no-pager --full status backup-gdrive.service | head -n 15
tail -n 30 logs/backup-wrapper.log
```
