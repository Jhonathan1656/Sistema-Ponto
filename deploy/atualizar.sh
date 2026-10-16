#!/usr/bin/env bash
# Atualizacao do dia a dia NO VPS (depois da migracao): puxa o codigo do
# GitHub, gera o build do Flutter aqui mesmo e reinicia o que mudou.
#   bash /opt/ponto/deploy/atualizar.sh
set -euo pipefail

DIR=/opt/ponto
FLUTTER_IMAGE="${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

cd "$DIR"
log "Puxando codigo"
git pull --ff-only

log "Guardando o build atual em /root/web-backup"
rm -rf /root/web-backup
cp -a frontend/build/web /root/web-backup

log "Build do Flutter ($FLUTTER_IMAGE)"
if ! docker run --rm -v "$DIR/frontend:/app" -w /app "$FLUTTER_IMAGE" \
    sh -c "git config --global --add safe.directory '*'; flutter pub get && flutter build web --release --no-wasm-dry-run"; then
  log "Build falhou: voltando o build anterior"
  rm -rf frontend/build/web
  cp -a /root/web-backup frontend/build/web
  exit 1
fi

log "Reiniciando backend e frontend"
docker compose up -d --build backend
docker compose up -d --force-recreate frontend
docker compose ps
log "ATUALIZADO-OK"
