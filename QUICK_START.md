# 🚀 Guia Rápido de Instalação

## Passo 1: Backend (5 minutos)

```bash
# 1. Entre na pasta do backend
cd backend

# 2. Crie ambiente virtual
python -m venv venv

# 3. Ative o ambiente
# Windows:
venv\Scripts\activate
# Linux/Mac:
source venv/bin/activate

# 4. Instale dependências
pip install -r requirements.txt

# 5. Execute o servidor
python main.py
```

✅ Backend rodando em: http://localhost:8000

## Passo 2: Frontend (5 minutos)

```bash
# 1. Entre na pasta do frontend
cd frontend

# 2. Instale dependências
flutter pub get

# 3. Execute o app
flutter run
```

## Passo 3: Primeiro Acesso

1. Abra o app
2. Clique em "Cadastre-se"
3. Preencha seus dados:
   - Nome: Seu Nome
   - Email: seu@email.com
   - CPF: 12345678900
   - Senha: sua_senha
4. Faça login
5. Comece a usar!

## Passo 4: Migrar do AppSheet (Opcional)

```bash
# 1. Exporte dados do AppSheet para CSV
# 2. Coloque os arquivos em migration/
# 3. Execute:
cd migration
pip install -r requirements.txt
python migrate_from_appsheet.py
```

## ⚠️ Problemas Comuns

### "Erro ao conectar API"
→ Verifique se o backend está rodando na porta 8000

### "Module not found"
→ Certifique-se de estar no ambiente virtual ativado

### App não conecta no celular
→ Use o IP da sua máquina ao invés de localhost:
```dart
// Em api_service.dart:
static const String baseUrl = 'http://192.168.1.X:8000';
```

## 📞 Ajuda

Problemas? Verifique o README.md completo ou crie uma issue!
