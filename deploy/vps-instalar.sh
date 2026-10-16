#!/usr/bin/env bash
# Prepara um VPS Ubuntu 24.04 para o VMac Ponto (passo 1 da migracao).
# Pode rodar mais de uma vez. NAO liga o site: o PC continua servindo ate a
# virada (vps-ativar.sh).
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/vmacprocessamento-alt/Sistema-Ponto.git}"
DIR=/opt/ponto
log() { echo "[$(date +%H:%M:%S)] $*"; }

[ "$(id -u)" = 0 ] || { echo "Rode como root."; exit 1; }
export DEBIAN_FRONTEND=noninteractive

log "Fuso horario: America/Sao_Paulo"
timedatectl set-timezone America/Sao_Paulo || true

log "Pacotes base"
apt-get update -y
apt-get install -y ca-certificates curl git ufw fail2ban

if ! command -v docker >/dev/null 2>&1; then
  log "Instalando Docker"
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
docker compose version

if ! command -v cloudflared >/dev/null 2>&1; then
  log "Instalando cloudflared (tunel da Cloudflare)"
  install -d -m 0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
    > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -y
  apt-get install -y cloudflared
fi
cloudflared --version

log "Firewall: entrada so por SSH (o site chega pelo tunel da Cloudflare)"
ufw allow OpenSSH
ufw --force enable
systemctl enable --now fail2ban

if [ -d "$DIR/.git" ]; then
  log "Atualizando codigo em $DIR"
  git -C "$DIR" pull --ff-only
else
  log "Baixando codigo para $DIR"
  git clone "$REPO_URL" "$DIR"
fi

cd "$DIR"
# Se o codigo do GitHub ainda nao tiver a pasta deploy/, usa a copia enviada.
if [ ! -f deploy/docker-compose.vps.yml ]; then
  mkdir -p deploy
  cp /root/migracao/docker-compose.vps.yml deploy/
fi
# O compose exige o backend/.env ate para baixar imagens. O verdadeiro chega
# na virada (vps-ativar.sh) e substitui este vazio.
[ -f backend/.env ] || touch backend/.env
# Portas so no 127.0.0.1 do VPS: o Docker passa por cima do ufw, e com as
# portas abertas o backend ficaria exposto no IP publico sem a Cloudflare.
echo 'COMPOSE_FILE=docker-compose.yml:deploy/docker-compose.vps.yml' > .env

log "Baixando/montando as imagens (o site ainda nao sobe)"
docker compose pull frontend
docker compose build backend

log "VPS-PREPARADO-OK"
