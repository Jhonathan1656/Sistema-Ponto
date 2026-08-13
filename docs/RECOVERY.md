# Recuperação Automática (queda de energia / reboot)

Objetivo: **se o PC desligar, assim que a energia voltar ele liga sozinho, o
Docker sobe junto e as aplicações voltam ao ar sem ninguém tocar em nada.**

## A corrente de recuperação

Cada elo depende do anterior. Se um quebra, os de baixo nunca acontecem.

| # | Elo | Como está garantido |
|---|-----|---------------------|
| 1 | PC religa quando a energia volta | **BIOS — você precisa configurar à mão** (ver abaixo) |
| 2 | Windows entra na sessão sozinho | Autologon (`AutoAdminLogon=1`) — já ativo |
| 3 | Boot limpo, sem estado híbrido | Fast Startup desligado — `setup-autostart.ps1` |
| 4 | Docker Desktop inicia | Chave `Run` + `AutoStart` — `setup-autostart.ps1` |
| 5 | Containers sobem | Task `PontoAutostart` + `restart: always` |
| 6 | Continuam de pé | Task `PontoWatchdog` (5 em 5 min) |
| 7 | Usuários alcançam o site | Serviço `Cloudflared` (LocalSystem, automático) |

### Como os usuários chegam

O acesso externo é `https://ponto.vmacengenharia.com`, servido por **Cloudflare
Tunnel**: a Cloudflare termina o TLS e o `cloudflared` local entrega no nginx da
porta 8080 em HTTP puro.

O `cloudflared` roda como serviço do Windows sob `LocalSystem`, com início
automático e ação de falha "reiniciar em 20s". Isso o torna o elo *mais* robusto
da corrente — diferente do Docker Desktop, ele não depende de logon.

Mas ele é um ponto único de falha invisível: se o túnel não voltar, os usuários
veem **erro 1033 da Cloudflare** enquanto tudo localmente parece perfeito. Por
isso o `check-recovery.ps1` testa a URL pública, não só o `localhost` — checar só
o local daria verde com o site inacessível.

## O que você precisa fazer (uma vez)

### 1. BIOS — o passo mais importante

**Sem isso nada mais funciona: o PC simplesmente não liga quando a energia volta.**

Entre na BIOS (F2 ou Del no boot) e procure, geralmente em *Power Management* /
*Advanced* / *ACPI*:

```
Restore on AC Power Loss   ->  Power On
```

Outros nomes para a mesma opção, conforme a placa:
`AC Power Recovery`, `After Power Failure`, `PWRON After PWR-Fail`,
`State After Power Loss`. O valor certo é **Power On** / **Last State** —
nunca *Power Off* / *Stay Off*.

### 2. Instalar as tarefas agendadas

PowerShell **como administrador**, na pasta do projeto:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-autostart.ps1
```

Isso registra `PontoAutostart` e `PontoWatchdog`, remove o atalho antigo da
pasta Startup, desliga o Fast Startup e garante o autostart do Docker Desktop.

### 3. Nobreak (UPS) — recomendado

O nobreak não é para manter o sistema no ar durante um apagão longo. Ele serve
para **desligar limpo** e absorver picos:

- Pico de tensão corrompe disco e queima fonte; o nobreak filtra.
- Desligamento sujo no meio de um write é o que corrompe banco de dados.
- Com 10-15 min de autonomia, a maioria das quedas curtas nem derruba o serviço.

Um nobreak de 600-1500VA com USB já resolve. Ligado por USB, o Windows o
reconhece como bateria e desliga sozinho quando a carga acaba.

## Como testar

Teste real (fora do horário de expediente): **puxe o cabo da tomada** com o
sistema rodando. Religue e cronometre até `http://localhost:8080` responder.
Espere algo entre 3 e 8 minutos — o Docker Desktop é a parte lenta.

Testes parciais, sem derrubar a máquina:

```powershell
# container morre -> watchdog recria
docker compose stop backend
.\watchdog-windows.ps1
docker compose ps

# simular o boot inteiro (sem reiniciar)
docker compose down
.\autostart-windows.ps1
```

## Onde olhar quando algo der errado

```powershell
# log do autostart e do watchdog
Get-Content "$env:LOCALAPPDATA\ponto-autostart.log" -Tail 40

# as tarefas rodaram?
Get-ScheduledTaskInfo -TaskName PontoAutostart
Get-ScheduledTaskInfo -TaskName PontoWatchdog

# saúde dos containers
docker compose ps
docker inspect --format '{{.State.Health.Status}}' ponto-system-backend-1
```

O log só registra eventos — se a stack está saudável, o watchdog fica calado de
propósito (rodando a cada 5 min, "tudo ok" viraria ruído e esconderia o que
importa).

## Detalhes de implementação

**`restart: always` em vez de `unless-stopped`.** Com `unless-stopped`, um
container parado à mão uma única vez nunca mais volta — nem depois de reboot.
Numa máquina que precisa se recuperar sozinha isso é uma bomba-relógio.

**Healthcheck + watchdog andam juntos.** O healthcheck do Docker Compose *não*
reinicia nada: só marca o container como `unhealthy` (quem reinicia é o Swarm).
Um backend travado — processo vivo, respondendo erro — nunca morre, então o
`restart: always` também não pega esse caso. Por isso existe o
`watchdog-windows.ps1`.

**`/health` não toca no Firestore.** A sonda roda a cada 30s; consultar o
Firestore aí comeria cota à toa. O endpoint só confirma que o processo responde.

**SQLite em WAL + `synchronous=FULL`.** Só a tabela `signature_documents`
(ZapSign) vive em SQLite; o resto dos dados está no Firestore. Com WAL o commit
vira append e o `FULL` força o fsync antes de confirmar, então uma queda de
energia no meio de um write custa a transação em andamento, não o banco inteiro.

**Redirect do gate precisa ser relativo.** O nginx escuta na 80 dentro do
container e recebe HTTP puro do túnel, então o `$scheme` que ele enxerga é
`http`. Com `absolute_redirect` ligado (o padrão), o 302 do gate de acesso saía
como `http://ponto.vmacengenharia.com/...` — rebaixando de HTTPS para HTTP e
perdendo a porta em acessos locais por `:8080`. Com `absolute_redirect off` o
Location sai relativo e o navegador preserva esquema, host e porta sozinho.

## Por que não Kubernetes

Kubernetes rodando nesta mesma máquina não protegeria contra queda de energia
nem contra o servidor morrer — se o PC desliga, o cluster desliga junto. O que
ele traz (self-healing, rolling deploy, config declarativa) está coberto aqui
pelo healthcheck + watchdog, com muito menos peça para dar errado no boot.

Kubernetes só passaria a fazer sentido com **duas ou mais máquinas** ou na
nuvem. Nesse cenário seria preciso, antes, tirar a tabela `signature_documents`
do SQLite local e resolver o diretório de backups, que hoje também é local — e
o job de auto-fechamento de pausas teria que virar singleton, senão duas
réplicas o executariam em duplicidade.
