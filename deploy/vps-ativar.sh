#!/usr/bin/env bash
# Virada (passo 2): recebe os dados do PC, sobe o sistema no VPS e liga o
# tunel da Cloudflare aqui. Chamado pelo 2-virar-para-vps.ps1 do PC.
set -euo pipefail

DIR=/opt/ponto
MIG=/root/migracao
PKG="$MIG/ponto-migracao.tgz"
TOKEN_FILE="$MIG/tunnel-token"
log() { echo "[$(date +%H:%M:%S)] $*"; }

cd "$DIR"
git pull --ff-only || log "aviso: git pull falhou; seguindo com o codigo que ja esta aqui"
echo 'COMPOSE_FILE=docker-compose.yml:deploy/docker-compose.vps.yml' > .env

log "Restaurando dados do PC (.env, service-account, banco, backups, build do site)"
[ -f "$PKG" ] || { echo "Pacote $PKG nao encontrado"; exit 1; }
tar -xzf "$PKG" -C "$DIR"
sed -i 's/\r$//' backend/.env
chmod 600 backend/.env backend/service-account.json
test -f frontend/build/web/index.html
test -f backend/data/ponto.db

log "Subindo backend e frontend"
docker compose up -d --build

log "Esperando ficar saudavel"
ok=""
for _ in $(seq 1 60); do
  b=$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q backend)" 2>/dev/null || true)
  f=$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q frontend)" 2>/dev/null || true)
  if [ "$b" = healthy ] && [ "$f" = healthy ]; then ok=1; break; fi
  sleep 5
done
docker compose ps
[ -n "$ok" ] || { echo "Stack nao ficou saudavel"; docker compose logs --tail 40; exit 1; }

log "Testes locais"
curl -fsS http://127.0.0.1:8000/health
echo
curl -fsS http://127.0.0.1:8080/access/unlock | grep -q "Palavra-chave"
echo "pagina de acesso ok"
if ss -ltn | grep -E '0\.0\.0\.0:(8000|8080)|\[::\]:(8000|8080)'; then
  echo "ERRO: porta aberta para a internet"; exit 1
fi
echo "portas so locais ok"

if [ -f "$TOKEN_FILE" ]; then
  log "Ligando o tunel da Cloudflare neste VPS"
  if systemctl list-unit-files | grep -q '^cloudflared\.service'; then
    cloudflared service uninstall || true
  fi
  cloudflared service install "$(tr -d '\r\n ' < "$TOKEN_FILE")"
  rm -f "$TOKEN_FILE"
  systemctl enable --now cloudflared
  for _ in $(seq 1 30); do
    if journalctl -u cloudflared --since "-3min" --no-pager | grep -q "Registered tunnel connection"; then
      echo "tunel conectado"; break
    fi
    sleep 2
  done
  journalctl -u cloudflared --since "-3min" --no-pager | grep -q "Registered tunnel connection" \
    || { echo "Tunel nao conectou"; journalctl -u cloudflared --no-pager | tail -20; exit 1; }
fi

log "VPS-ATIVO-OK"
