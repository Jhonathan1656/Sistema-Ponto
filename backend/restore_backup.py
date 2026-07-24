#!/usr/bin/env python3
"""Descriptografa um backup .enc gerado pelo email semanal.

Uso:
    python restore_backup.py backup-YYYYMMDD-HHMMSS.zip.enc [saida.zip]

A senha vem de BACKUP_ZIP_PASSWORD (env) ou e pedida interativamente.
Gera de volta o .zip com firestore.json + ponto.db.
"""
import base64
import getpass
import hashlib
import os
import sys

try:
    from cryptography.fernet import Fernet
except ImportError:
    sys.exit("Instale a lib: pip install cryptography")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    enc_path = sys.argv[1]
    if not os.path.exists(enc_path):
        sys.exit(f"Arquivo nao encontrado: {enc_path}")

    out_path = sys.argv[2] if len(sys.argv) > 2 else (
        enc_path[:-4] if enc_path.endswith(".enc") else enc_path + ".zip"
    )

    password = os.getenv("BACKUP_ZIP_PASSWORD") or getpass.getpass(
        "Senha do backup (BACKUP_ZIP_PASSWORD): "
    )
    key = base64.urlsafe_b64encode(hashlib.sha256(password.encode("utf-8")).digest())

    with open(enc_path, "rb") as handle:
        token = handle.read()
    try:
        data = Fernet(key).decrypt(token)
    except Exception:
        sys.exit("Falha ao descriptografar: senha incorreta ou arquivo corrompido.")

    with open(out_path, "wb") as handle:
        handle.write(data)
    print(f"OK: {out_path} ({len(data)} bytes). Descompacte para firestore.json + ponto.db.")


if __name__ == "__main__":
    main()
