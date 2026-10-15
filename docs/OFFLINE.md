# Modo offline (web / PWA)

O app em `ponto.vmacengenharia.com` abre e registra ponto sem internet depois
de **uma** abertura com internet (login feito). Os pontos ficam guardados no
aparelho e sobem sozinhos quando o sinal volta.

## O que acontece sem internet

| Etapa | Como funciona |
|---|---|
| Abrir o app | O service worker (`frontend/web/pwa_service_worker.js`) serve a copia salva de `index.html`, `main.dart.js`, canvaskit e assets. |
| Texto na tela | A fonte Roboto vem embutida no app (`frontend/assets/fonts`, declarada no `pubspec.yaml`). Sem ela o Flutter web baixa a Roboto do `fonts.gstatic.com` e, offline, a tela abria com cores e icones mas **sem nenhum texto** (visto no iPhone). Fontes extras que o Flutter busca para simbolos tambem vao para o cache `vmac-ponto-vendor`. |
| Firebase iniciar | O SDK JS do Firebase (`www.gstatic.com/firebasejs/...`) tambem fica no cache do service worker. Sem isso o app parava em "Nao foi possivel iniciar o aplicativo". |
| Sessao | O Firebase Auth guarda a sessao no IndexedDB; nao pede senha de novo. |
| Perfil e pontos do dia | O cache local do Firestore (ligado em `frontend/lib/main.dart`) devolve o que foi lido online por ultimo. A tela mostra o status certo (ex.: "Em servico") mesmo offline. |
| Bater ponto | `ApiService.createTimeRecord` detecta a falta de rede e grava na fila local (`SharedPreferences`), com id de documento ja definido. A tela avisa "Sem internet. Registro salvo no aparelho". |
| Internet volta | `HomeScreen` sincroniza ao detectar conexao, a cada 60 s e no puxar-para-atualizar. Cada registro e gravado no Firestore com o mesmo id, entao nao duplica. |
| Estagiario | Entrada/saida passam pelo backend (`/work-schedule/punch`). Sem rede, o ponto vai para a fila e a sincronizacao reenvia pelo mesmo endpoint, com as regras de horario. |

## Regras importantes

- **Primeira vez precisa de internet.** O cache so existe depois de uma
  abertura online completa (tela de ponto carregada). Oriente a equipe a abrir
  o app no escritorio antes de ir para o campo.
- **A hora registrada e a do aparelho.** Igual ao modo online: o campo
  `timestamp` vem do celular; `created_at` (hora do servidor) so e preenchido
  quando o registro chega ao Firestore. Para auditar, compare os dois.
- **Instalar como app** (menu do navegador > "Adicionar a tela inicial") e
  recomendado: o navegador preserva melhor o cache de apps instalados.
- Limpar os dados do site no navegador apaga o cache E a fila de pontos que
  ainda nao subiu. Antes de limpar, confira na tela inicial se ha
  "registro(s) aguardando internet".

## Atualizacoes do app

- Online, o service worker busca sempre a versao publicada (rede primeiro) e
  atualiza a copia local. Nao ha lista de versao para manter.
- O nginx manda `Cache-Control: no-cache` para js/wasm/json: o navegador pode
  guardar, mas revalida com ETag. Arquivo que nao mudou custa um 304.
- Para forcar uma limpeza geral do cache (raro), mude `CACHE_VERSION` em
  `pwa_service_worker.js`; a proxima abertura online descarta o cache antigo.

## Deploy

Nada novo: `flutter build web --release` copia `web/pwa_service_worker.js` e
`web/index.html` para `build/web`, e o `docker compose up -d` publica. Confira
que o `nginx.conf` em producao e o do repositorio (cabecalhos `no-cache`).

## Teste rapido

1. Abra o app com internet, faca login e espere a tela de ponto.
2. Ative o modo aviao.
3. Feche o app e abra de novo: deve carregar e mostrar o status do dia.
4. Bata um ponto: aparece "Sem internet. Registro salvo no aparelho" e o
   registro na lista com o icone de sincronizacao pendente.
5. Desligue o modo aviao: em ate 60 s o aviso "registro(s) aguardando
   internet" some e o ponto aparece no Firestore.

## Diagnostico

No Chrome: `chrome://inspect` (celular via USB) ou DevTools > Application:

- **Service Workers**: `pwa_service_worker.js` deve estar "activated".
- **Cache Storage**: `vmac-ponto-shell-v1` (arquivos do site) e
  `vmac-ponto-vendor-v1` (SDK do Firebase e fontes do Google).
- **IndexedDB**: `firebaseLocalStorageDb` (sessao) e `firestore/...` (cache
  de dados).
