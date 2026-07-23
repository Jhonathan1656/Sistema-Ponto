# 🏗️ Arquitetura do Sistema de Ponto

## Visão Geral

```
┌─────────────────────────────────────────────────────────────────┐
│                         FRONTEND (Flutter)                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │  Login   │  │   Home   │  │Dashboard │  │ Histórico│       │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              ApiService (HTTP Client)                     │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────┬───────────────────────────────────────┘
                          │ HTTP/JSON
                          │ (REST API)
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                      BACKEND (FastAPI)                           │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                  Rotas da API                             │  │
│  │  • POST /token (Login)                                    │  │
│  │  • POST /register (Cadastro)                              │  │
│  │  • GET  /me (Usuário atual)                               │  │
│  │  • POST /time-record (Registrar ponto)                    │  │
│  │  • GET  /time-records (Listar registros)                  │  │
│  │  • GET  /work-summary (Resumo de horas)                   │  │
│  │  • GET  /export-timesheet (Exportar PDF)                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                          │                                       │
│  ┌──────────────────────▼────────────────────────────────────┐ │
│  │              Autenticação JWT                             │ │
│  │  • Geração de tokens                                      │ │
│  │  • Validação de tokens                                    │ │
│  │  • Hash de senhas (bcrypt)                                │ │
│  └──────────────────────────────────────────────────────────┘  │
│                          │                                       │
│  ┌──────────────────────▼────────────────────────────────────┐ │
│  │              ORM (SQLAlchemy)                             │ │
│  │  • Models: User, TimeRecord                               │ │
│  │  • Queries automáticas                                    │ │
│  │  • Validações (Pydantic)                                  │ │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                   BANCO DE DADOS (SQLite)                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐      ┌──────────────────┐                │
│  │   Tabela: users  │      │ Tabela: records  │                │
│  ├──────────────────┤      ├──────────────────┤                │
│  │ • id             │      │ • id             │                │
│  │ • email          │◄─────┤ • user_id (FK)   │                │
│  │ • name           │      │ • timestamp      │                │
│  │ • cpf            │      │ • record_type    │                │
│  │ • password_hash  │      │ • location       │                │
│  │ • role           │      │ • notes          │                │
│  │ • daily_hours    │      └──────────────────┘                │
│  │ • is_active      │                                           │
│  └──────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘
```

## Fluxo de Dados

### 1. Login
```
App → POST /token → Backend → Valida credenciais → Gera JWT → Retorna token
```

### 2. Registro de Ponto
```
App → POST /time-record (+ JWT) → Backend → Valida token → Salva no DB → Retorna confirmação
```

### 3. Dashboard
```
App → GET /work-summary (+ JWT) → Backend → Busca registros → Calcula horas → Retorna resumo
```

### 4. Exportação
```
App → GET /export-timesheet → Backend → Busca dados → Gera PDF → Retorna arquivo
```

## Segurança

```
┌──────────────────────────────────────────┐
│         Camadas de Segurança             │
├──────────────────────────────────────────┤
│ 1. HTTPS/TLS (Transporte)                │
│ 2. JWT (Autenticação)                    │
│ 3. Bcrypt (Senhas)                       │
│ 4. CORS (Cross-Origin)                   │
│ 5. Validação (Pydantic)                  │
│ 6. ORM (SQL Injection)                   │
└──────────────────────────────────────────┘
```

## Escalabilidade

### Atual (Fase 1)
```
Flutter App → FastAPI → SQLite
```

### Futura (Fase 2 - Crescimento)
```
                    ┌─> FastAPI Instance 1 ─┐
Flutter App → LB →──┤                        ├─> PostgreSQL
                    └─> FastAPI Instance 2 ─┘
                            ↓
                         Redis (Cache)
```

### Empresarial (Fase 3)
```
                    ┌─> Auth Service ────────┐
                    │                         │
Flutter App → API ──┼─> Ponto Service ───────┤─> PostgreSQL
Gateway             │                         │
                    └─> Export Service ───────┘
                            ↓
                    ┌─> Queue (RabbitMQ)
                    └─> Storage (S3)
```

## Tecnologias

### Frontend
- **Flutter**: Framework multiplataforma
- **Dart**: Linguagem
- **HTTP**: Cliente REST
- **FL Chart**: Gráficos
- **PDF**: Geração de documentos

### Backend
- **Python 3.11+**: Linguagem
- **FastAPI**: Framework web
- **SQLAlchemy**: ORM
- **Pydantic**: Validação
- **JWT**: Autenticação
- **Bcrypt**: Criptografia

### Infraestrutura
- **SQLite**: Banco (dev/pequeno)
- **PostgreSQL**: Banco (produção)
- **Nginx**: Proxy reverso
- **Docker**: Containerização
- **Systemd**: Gerenciamento de serviços
