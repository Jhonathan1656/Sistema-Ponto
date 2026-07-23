# Sistema de Registro de Ponto

Sistema completo de controle de ponto eletrônico com backend Python (FastAPI) e frontend Flutter.

## 📋 Funcionalidades

### ✅ Já Implementadas

- **Autenticação e Segurança**
  - Login e registro de usuários
  - Autenticação JWT
  - Controle de acesso por roles (funcionário, gerente, admin)

- **Registro de Ponto**
  - Entrada e saída
  - Pausas (início e fim)
  - Geolocalização (opcional)
  - Observações personalizadas

- **Dashboard**
  - Visualização de horas normais e extras
  - Gráficos de horas trabalhadas
  - Consolidação mensal
  - Detalhamento diário

- **Histórico**
  - Consulta de registros por data
  - Filtros personalizados
  - Visualização detalhada

- **Exportação**
  - Geração de PDF para contabilidade
  - Relatório completo com totalizadores
  - Formato profissional

## 📚 Documentação

| Documento | Conteúdo |
|---|---|
| [QUICK_START.md](docs/QUICK_START.md) | Subir o projeto rapidamente |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Decisões de arquitetura e fluxo de dados |
| [FEATURES.md](docs/FEATURES.md) | Funcionalidades detalhadas |
| [DEPLOY.md](docs/DEPLOY.md) | Publicação em produção |
| [OPERATIONAL_CONFIG.md](docs/OPERATIONAL_CONFIG.md) | Configuração operacional |

## 🏗️ Arquitetura

```
ponto-system/
├── backend/                    # API Python FastAPI
│   ├── main.py                # Aplicação principal
│   ├── work_schedule_rules.py # Regras de jornada
│   ├── seed_data.py           # Carga inicial
│   ├── update_user_role.py    # Utilitário de roles
│   ├── requirements.txt
│   ├── Dockerfile
│   └── data/ponto.db          # SQLite (gerado, fora do git)
│
├── frontend/                   # App Flutter
│   ├── lib/
│   │   ├── main.dart
│   │   ├── firebase_options.dart
│   │   ├── screens/           # Telas (login, dashboard, chat, admin…)
│   │   ├── services/          # API, config, notificações, export
│   │   ├── utils/             # Helpers
│   │   └── widgets/           # Componentes reutilizáveis
│   ├── assets/                # Imagens e templates Excel
│   └── pubspec.yaml
│
├── migration/                  # Scripts de migração do AppSheet
│   ├── migrate_from_appsheet.py
│   └── requirements.txt
│
├── docs/                       # Documentação (ver tabela acima)
├── openspec/                   # Propostas e specs de mudança
│
├── docker-compose.yml          # Orquestração backend + nginx
├── nginx.conf                  # Proxy do frontend web
├── firebase.json               # Config Firebase
└── firestore.rules             # Regras de segurança Firestore
```

## 🚀 Como Executar

### Backend (Python)

1. **Instalar dependências:**
```bash
cd backend
python -m venv venv
source venv/bin/activate  # No Windows: venv\Scripts\activate
pip install -r requirements.txt
```

2. **Executar servidor:**
```bash
python main.py
```

O servidor estará disponível em: `http://localhost:8000`

3. **Acessar documentação da API:**
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

### Frontend (Flutter)

1. **Instalar dependências:**
```bash
cd frontend
flutter pub get
```

2. **Configurar URL da API:**
Edite o arquivo `lib/services/api_service.dart` e altere:
```dart
static const String baseUrl = 'http://SEU-SERVIDOR:8000';
```

3. **Executar app:**
```bash
# Android
flutter run

# iOS
flutter run

# Web
flutter run -d chrome
```

## 📊 Migração de Dados do AppSheet

1. **Exportar dados do AppSheet:**
   - Vá para o AppSheet
   - Exporte as tabelas como CSV
   - Salve como `users.csv` e `time_records.csv`

2. **Preparar arquivos CSV:**

**users.csv:**
```csv
id,email,name,cpf,role,daily_hours
1,joao@email.com,João Silva,12345678900,employee,8.0
2,maria@email.com,Maria Santos,98765432100,manager,8.0
```

**time_records.csv:**
```csv
id,user_id,timestamp,type,location,notes
1,1,2024-01-15T08:00:00,check_in,Escritório,
2,1,2024-01-15T17:00:00,check_out,Escritório,
```

3. **Executar migração:**
```bash
cd migration
pip install -r requirements.txt
python migrate_from_appsheet.py
```

## 🔧 Configuração

### Variáveis de Ambiente (Backend)

Crie um arquivo `.env` na pasta `backend`:

```env
SECRET_KEY=sua-chave-secreta-super-segura-aqui
DATABASE_URL=sqlite:///./ponto.db
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

### Configurações do App (Flutter)

Edite `lib/services/api_service.dart`:
```dart
static const String baseUrl = 'http://seu-servidor.com:8000';
```

## 📱 Telas do App

### 1. Login
- Email e senha
- Link para cadastro
- Validação de campos

### 2. Cadastro
- Nome completo
- Email
- CPF (com formatação automática)
- Senha e confirmação

### 3. Home (Registro de Ponto)
- Relógio em tempo real
- Botões de ação contextuais:
  - Registrar Entrada
  - Iniciar/Encerrar Pausa
  - Registrar Saída
- Status atual do funcionário

### 4. Dashboard
- Seletor de mês
- Cards de resumo:
  - Horas normais
  - Horas extras
- Gráfico de horas por dia
- Lista detalhada com:
  - Horário de entrada/saída
  - Total de horas
  - Horas extras destacadas

### 5. Histórico
- Seletor de data
- Lista de todos os registros do dia
- Detalhes de cada marcação

### 6. Perfil
- Informações do usuário
- Exportação de folha de ponto (PDF)
- Logout

## 🔐 Segurança

- **Autenticação JWT:** Tokens com expiração configurável
- **Senhas:** Hash bcrypt
- **CORS:** Configurado para aceitar origens específicas
- **SQL Injection:** Proteção via ORM SQLAlchemy
- **Validação:** Pydantic para validação de dados

## 📦 Dependências Principais

### Backend
- FastAPI: Framework web
- SQLAlchemy: ORM
- Passlib: Hash de senhas
- Python-JOSE: JWT
- Uvicorn: Servidor ASGI

### Frontend
- http/dio: Cliente HTTP
- provider: Gerenciamento de estado
- shared_preferences: Armazenamento local
- fl_chart: Gráficos
- pdf: Geração de PDFs
- intl: Internacionalização

## 🎨 Personalização

### Mudar cores do app:
Edite `frontend/lib/main.dart`:
```dart
theme: ThemeData(
  primarySwatch: Colors.blue, // Mude aqui
  // ...
),
```

### Ajustar carga horária padrão:
Backend `main.py`:
```python
daily_hours = Column(Float, default=8.0)  # Mude aqui
```

## 📈 Próximas Melhorias

- [ ] Notificações push
- [ ] Modo offline
- [ ] Reconhecimento facial
- [ ] Integração com sistemas de RH
- [ ] App para gestores
- [ ] Relatórios avançados
- [ ] Banco de horas
- [ ] Múltiplas empresas

## 🆘 Troubleshooting

### Erro de conexão com API
- Verifique se o backend está rodando
- Confirme a URL em `api_service.dart`
- Verifique firewall/porta 8000

### Erro de CORS
- Ajuste `allow_origins` no backend
- Use IP real ao invés de localhost em dispositivos móveis

### Erro de migração
- Confirme formato dos CSVs
- Verifique nomes das colunas
- Crie usuário admin primeiro

## 📝 Licença

Este projeto é de código aberto para uso educacional e comercial.

## 👥 Suporte

Para dúvidas e suporte:
- Crie uma issue no repositório
- Email: suporte@seudominio.com

---

Desenvolvido com ❤️ usando Flutter e Python
