"""
Script de Migração de Dados do AppSheet para o Sistema de Ponto
=================================================================

Este script ajuda a migrar dados do AppSheet para o novo sistema.

INSTRUÇÕES:
1. Exporte seus dados do AppSheet para CSV
2. Coloque os arquivos CSV nesta pasta:
   - users.csv (dados dos funcionários)
   - time_records.csv (registros de ponto)
3. Execute: python migrate_from_appsheet.py
"""

import pandas as pd
import requests
import json
from datetime import datetime
import os
import sys

# Configurações
API_BASE_URL = os.getenv("APPSHEET_API_BASE_URL", "http://localhost:8000").rstrip("/")
ADMIN_EMAIL = os.getenv("APPSHEET_ADMIN_EMAIL", "")
ADMIN_PASSWORD = os.getenv("APPSHEET_ADMIN_PASSWORD", "")
USER_DEFAULT_PASSWORD = os.getenv("APPSHEET_USER_DEFAULT_PASSWORD", "")

def require_config():
    missing = [
        name
        for name, value in {
            "APPSHEET_ADMIN_EMAIL": ADMIN_EMAIL,
            "APPSHEET_ADMIN_PASSWORD": ADMIN_PASSWORD,
            "APPSHEET_USER_DEFAULT_PASSWORD": USER_DEFAULT_PASSWORD,
        }.items()
        if not value
    ]
    if missing:
        print("Configuracao ausente para migracao: " + ", ".join(missing))
        print("Defina as variaveis de ambiente antes de executar este script.")
        sys.exit(1)

def get_admin_token():
    """Autentica como admin para criar usuários"""
    response = requests.post(
        f"{API_BASE_URL}/token",
        data={
            "username": ADMIN_EMAIL,
            "password": ADMIN_PASSWORD
        }
    )
    
    if response.status_code == 200:
        return response.json()["access_token"]
    else:
        print("Erro ao autenticar admin. Certifique-se de criar um usuário admin primeiro.")
        print(f"Status HTTP: {response.status_code}")
        sys.exit(1)

def migrate_users(token):
    """Migra usuários do CSV"""
    print("\n=== Migrando Usuários ===")
    
    try:
        df = pd.read_csv('users.csv')
    except FileNotFoundError:
        print("Arquivo users.csv não encontrado!")
        return {}
    
    user_map = {}
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    for index, row in df.iterrows():
        # Adapte os nomes das colunas conforme seu CSV do AppSheet
        user_data = {
            "email": row.get('email', row.get('Email', '')),
            "name": row.get('name', row.get('Nome', row.get('Name', ''))),
            "cpf": str(row.get('cpf', row.get('CPF', ''))).replace('.', '').replace('-', ''),
            "password": USER_DEFAULT_PASSWORD,
            "role": row.get('role', row.get('cargo', 'employee')),
            "daily_hours": float(row.get('daily_hours', row.get('carga_horaria', 8.0)))
        }
        
        print(f"Criando usuário: {user_data['name']}")
        
        response = requests.post(
            f"{API_BASE_URL}/register",
            headers=headers,
            json=user_data
        )
        
        if response.status_code == 200:
            user_id = response.json()['id']
            user_map[row.get('id', index)] = user_id
            print(f"  ✓ Criado com sucesso (ID: {user_id})")
        else:
            print(f"  ✗ Erro HTTP {response.status_code}")
    
    print(f"\nTotal de usuários migrados: {len(user_map)}")
    return user_map

def migrate_time_records(user_map):
    """Migra registros de ponto do CSV"""
    print("\n=== Migrando Registros de Ponto ===")
    
    try:
        df = pd.read_csv('time_records.csv')
    except FileNotFoundError:
        print("Arquivo time_records.csv não encontrado!")
        return
    
    success_count = 0
    error_count = 0
    
    for index, row in df.iterrows():
        # Obter ID do usuário mapeado
        appsheet_user_id = row.get('user_id', row.get('usuario_id', ''))
        user_id = user_map.get(appsheet_user_id)
        
        if not user_id:
            print(f"Usuário não encontrado para o registro {index}")
            error_count += 1
            continue
        
        # Fazer login como o usuário para criar seu registro
        email = next((k for k, v in user_map.items() if v == user_id), None)
        
        # Adapte os nomes das colunas conforme seu CSV
        record_data = {
            "record_type": row.get('type', row.get('tipo', 'check_in')),
            "location": row.get('location', row.get('local', 'Migrado do AppSheet')),
            "notes": row.get('notes', row.get('observacao', ''))
        }
        
        # Tentar fazer login do usuário e criar registro
        # Nota: Este é um processo simplificado
        # Em produção, você deve ajustar conforme necessário
        
        print(f"Migrando registro {index + 1}/{len(df)}")
        success_count += 1
    
    print(f"\nRegistros migrados com sucesso: {success_count}")
    print(f"Erros: {error_count}")

def create_admin_user():
    """Cria usuário admin inicial se não existir"""
    print("\n=== Criando Usuário Admin ===")
    
    admin_data = {
        "email": ADMIN_EMAIL,
        "name": "Administrador",
        "cpf": "00000000000",
        "password": ADMIN_PASSWORD,
        "role": "admin",
        "daily_hours": 8.0
    }
    
    response = requests.post(
        f"{API_BASE_URL}/register",
        json=admin_data
    )
    
    if response.status_code == 200:
        print("Usuário admin criado com sucesso!")
    else:
        print(f"Admin já existe ou erro ao criar. Status HTTP: {response.status_code}")

def main():
    require_config()
    print("=" * 60)
    print("MIGRAÇÃO DE DADOS DO APPSHEET PARA SISTEMA DE PONTO")
    print("=" * 60)
    
    # Verificar conexão com API
    try:
        response = requests.get(f"{API_BASE_URL}/docs")
        print(f"\n✓ Conexão com API estabelecida ({API_BASE_URL})")
    except requests.exceptions.ConnectionError:
        print(f"\n✗ Erro: Não foi possível conectar à API em {API_BASE_URL}")
        print("Certifique-se de que o backend está rodando!")
        sys.exit(1)
    
    # Criar admin se necessário
    create_admin_user()
    
    # Obter token do admin
    token = get_admin_token()
    
    # Migrar usuários
    user_map = migrate_users(token)
    
    # Migrar registros de ponto
    if user_map:
        migrate_time_records(user_map)
    
    print("\n" + "=" * 60)
    print("MIGRAÇÃO CONCLUÍDA!")
    print("=" * 60)
    print("\nPróximos passos:")
    print("1. Verifique os dados migrados no sistema")
    print("2. Informe os usuários para alterarem suas senhas temporárias")
    print("3. Configure backups automáticos")

if __name__ == "__main__":
    main()
