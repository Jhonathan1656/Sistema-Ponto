import os
import random
import shutil
import tempfile
import zipfile
import html
import re
import base64
import json
import sqlite3
import hashlib
import hmac
import secrets
import logging
from datetime import datetime, timedelta, time, date
from calendar import monthrange
from typing import Optional, List

import httpx
import openpyxl
from openpyxl.styles import Alignment, Font, Border, Side
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse, Response
from fastapi_mail import FastMail, MessageSchema, ConnectionConfig, MessageType
from pydantic import BaseModel
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

logger = logging.getLogger(__name__)

try:
    import firebase_admin
    from firebase_admin import auth as firebase_auth
    from firebase_admin import credentials, firestore, messaging
except ImportError:
    firebase_admin = None
    firebase_auth = None
    credentials = None
    firestore = None
    messaging = None

# --- CONFIGURAÇÕES ---
SECRET_KEY = os.getenv("SECRET_KEY", "sua-chave-secreta-aqui-mude-em-producao")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
ZAPSIGN_API_TOKEN = os.getenv("ZAPSIGN_API_TOKEN", "")
ZAPSIGN_API_BASE_URL = os.getenv(
    "ZAPSIGN_API_BASE_URL",
    "https://sandbox.api.zapsign.com.br/api/v1",
).rstrip("/")
ZAPSIGN_APP_URL = os.getenv(
    "ZAPSIGN_APP_URL",
    "https://sandbox.app.zapsign.com.br/verificar",
).rstrip("/")
ZAPSIGN_WEBHOOK_SECRET = os.getenv("ZAPSIGN_WEBHOOK_SECRET", "")
DATABASE_PATH = os.getenv("DATABASE_PATH", "/app/data/ponto.db")
FIREBASE_WEB_API_KEY = os.getenv("FIREBASE_WEB_API_KEY", "")
SHARED_ACCESS_TOKEN = os.getenv("SHARED_ACCESS_TOKEN", "")
SHARED_ACCESS_COOKIE = "ponto_access"

# Configurações de E-mail
MAIL_USERNAME = "vmac.rh.01@gmail.com"
# ATENÇÃO: Use uma "App Password" do Google, não a senha normal.
MAIL_PASSWORD = os.getenv("MAIL_PASSWORD", "mude-me")
MAIL_FROM = "vmac.rh.01@gmail.com"
MAIL_PORT = 587
MAIL_SERVER = "smtp.gmail.com"
MAIL_FROM_NAME = "Assistente VMac"

conf = ConnectionConfig(
    MAIL_USERNAME=MAIL_USERNAME,
    MAIL_PASSWORD=MAIL_PASSWORD,
    MAIL_FROM=MAIL_FROM,
    MAIL_PORT=MAIL_PORT,
    MAIL_SERVER=MAIL_SERVER,
    MAIL_FROM_NAME=MAIL_FROM_NAME,
    MAIL_STARTTLS=True,
    MAIL_SSL_TLS=False,
    USE_CREDENTIALS=True,
    VALIDATE_CERTS=True
)

# Regras de Horários e Valores (Conforme Ponto.py)
NORMAL_INI = time(13, 30)
NORMAL_FIM = time(19, 30)

RATE_NORMAL = 8.33
RATE_EXTRA = 8.33
RATE_50 = 12.50
RATE_100 = 16.66

# Colunas Buckets (M..T)
COL_M = 13; COL_N = 14; COL_O = 15; COL_P = 16
COL_Q = 17; COL_R = 18; COL_S = 19; COL_T = 20

# Resumo financeiro (B41:E44)
SUMMARY_ROW_TITLE = 41
SUMMARY_ROW_HOURS = 42
SUMMARY_ROW_VALUE = 43
SUMMARY_ROW_FINAL = 44
SUMMARY_START_COL = 2

app = FastAPI(title="Ponto System API")
security = HTTPBearer(auto_error=True)


def _shared_access_cookie_value() -> str:
    """Returns a signed value without exposing the shared access token."""
    return hmac.new(
        SECRET_KEY.encode("utf-8"),
        SHARED_ACCESS_TOKEN.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _safe_redirect_path(path: str) -> str:
    return path if path.startswith("/") and not path.startswith("//") else "/"


@app.get("/access/unlock", response_class=HTMLResponse)
async def access_unlock_form(next: str = "/"):
    safe_next = html.escape(_safe_redirect_path(next), quote=True)
    return f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Acesso ao Ponto</title><style>
body{{margin:0;min-height:100vh;display:grid;place-items:center;background:#f4f6f8;font-family:Arial,sans-serif;color:#18212b}}
main{{width:min(360px,calc(100% - 48px));background:#fff;padding:32px;border-radius:14px;box-shadow:0 12px 32px #0002}}
h1{{margin:0 0 10px;font-size:24px}}p{{margin:0 0 24px;color:#52606d;line-height:1.45}}label{{display:block;font-weight:600;margin-bottom:8px}}input{{box-sizing:border-box;width:100%;padding:13px;border:1px solid #b8c2cc;border-radius:8px;font-size:16px}}button{{width:100%;margin-top:16px;padding:13px;border:0;border-radius:8px;background:#1769aa;color:#fff;font-size:16px;font-weight:600;cursor:pointer}}
</style></head><body><main><h1>Acesso restrito</h1><p>Informe o token de acesso para continuar.</p>
<form method="post" action="/access/login"><input type="hidden" name="next" value="{safe_next}"><label for="token">Token de acesso</label><input id="token" name="token" type="password" autocomplete="current-password" autofocus required><button type="submit">Entrar</button></form>
</main></body></html>"""


@app.post("/access/login")
async def access_unlock(token: str = Form(...), next: str = Form("/")):
    if not SHARED_ACCESS_TOKEN or not secrets.compare_digest(token, SHARED_ACCESS_TOKEN):
        return HTMLResponse("<h1>Token inválido</h1><p><a href='/access/unlock'>Tentar novamente</a></p>", status_code=401)

    response = RedirectResponse(url=_safe_redirect_path(next), status_code=303)
    response.set_cookie(
        key=SHARED_ACCESS_COOKIE,
        value=_shared_access_cookie_value(),
        max_age=60 * 60 * 24 * 30,
        secure=True,
        httponly=True,
        samesite="lax",
    )
    return response


@app.get("/access/check")
async def access_check(request: Request):
    is_authorized = SHARED_ACCESS_TOKEN and secrets.compare_digest(
        request.cookies.get(SHARED_ACCESS_COOKIE, ""),
        _shared_access_cookie_value(),
    )
    return Response(status_code=204 if is_authorized else 401)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- AUXILIARES DE CÁLCULO (Lógica Ponto.py) ---

def minutes_between_str(s1: str, s2: str) -> int:
    try:
        t1 = datetime.strptime(s1, "%H:%M")
        t2 = datetime.strptime(s2, "%H:%M")
        diff = (t2 - t1).total_seconds() / 60
        if diff < 0: diff += 1440 # Virada de dia
        return int(diff)
    except: return 0

def classify_day_minutes(check_in: str, check_out: str, b_start: str = None, b_end: str = None) -> dict:
    total = minutes_between_str(check_in, check_out)
    if b_start and b_end:
        total -= minutes_between_str(b_start, b_end)

    total = max(0, total)
    res = {"normal": 0, "extras": 0, "extra_50": 0, "extra_100": 0}

    if total <= 360:
        res["normal"] = total
    else:
        res["normal"] = 360
        res["extras"] = total - 360

    return res

def split_hours_and_rem(total_min: int):
    return total_min // 60, total_min % 60

# --- GERAÇÃO AUTOMÁTICA (DO 0) ---

class ExportRecord(BaseModel):
    date: str
    check_in: Optional[str] = None
    check_out: Optional[str] = None
    break_start: Optional[str] = None
    break_end: Optional[str] = None
    entry_3: Optional[str] = None
    exit_3: Optional[str] = None
    total_hours: Optional[float] = None
    regular_hours: Optional[float] = None
    overtime_hours: Optional[float] = None
    extra_50: Optional[float] = None
    extra_100: Optional[float] = None

class EstagRules(BaseModel):
    saturday_50: bool = True
    sunday_100: bool = True
    night_100: bool = True

def night_minutes_between_str(s1: str, s2: str) -> int:
    try:
        start = datetime.strptime(s1, "%H:%M")
        end = datetime.strptime(s2, "%H:%M")
        if end <= start:
            end += timedelta(days=1)

        total = 0
        current_day = start.replace(hour=0, minute=0, second=0, microsecond=0)
        while current_day <= end:
            night_ranges = [
                (current_day, current_day.replace(hour=5)),
                (current_day.replace(hour=22), current_day + timedelta(days=1)),
            ]
            for night_start, night_end in night_ranges:
                overlap_start = max(start, night_start)
                overlap_end = min(end, night_end)
                if overlap_end > overlap_start:
                    total += int((overlap_end - overlap_start).total_seconds() / 60)
            current_day += timedelta(days=1)
        return total
    except Exception:
        return 0

def record_night_minutes(record: ExportRecord) -> int:
    total = 0
    pairs = [
        (record.check_in, record.check_out),
        (record.break_start, record.break_end),
        (record.entry_3, record.exit_3),
    ]
    for start, end in pairs:
        if start and end:
            total += night_minutes_between_str(start, end)
    return total

def classify_estag_payroll(record: ExportRecord, record_date: date, holiday_days: set, rules: Optional[EstagRules]) -> dict:
    mins = classify_day_minutes(record.check_in, record.check_out, record.break_start, record.break_end)
    result = {"normal": 0, "extras": 0, "50": 0, "100": 0}
    total = mins["normal"] + mins["extras"]
    rules = rules or EstagRules()

    if record_date.weekday() == 6 or record_date.day in holiday_days:
        if rules.sunday_100:
            result["100"] = total
        else:
            result["normal"] = mins["normal"]
            result["extras"] = mins["extras"]
        return result

    if record_date.weekday() == 5:
        if rules.saturday_50:
            result["50"] = total
        else:
            result["normal"] = mins["normal"]
            result["extras"] = mins["extras"]
        return result

    if rules.night_100:
        night = min(record_night_minutes(record), total)
        result["100"] = night
        remaining = total - night
        result["normal"] = min(mins["normal"], remaining)
        result["extras"] = max(remaining - result["normal"], 0)
        return result

    result["normal"] = mins["normal"]
    result["extras"] = mins["extras"]
    return result

def generate_scratch_records(year: int, month: int, total_hours: float) -> List[ExportRecord]:
    total_min = int(total_hours * 60)
    dias_uteis = []
    num_days = monthrange(year, month)[1]
    for d in range(1, num_days + 1):
        dt = date(year, month, d)
        if dt.weekday() != 6: dias_uteis.append(dt)

    if not dias_uteis: return []

    dist = [480 for _ in dias_uteis]
    rest = total_min - sum(dist)
    indices = list(range(len(dias_uteis)))
    random.shuffle(indices)
    for i in indices:
        if rest <= 0: break
        add = min(60, rest); dist[i] += add; rest -= add

    recs = []
    for dt, m in zip(dias_uteis, dist):
        ini = random.choice(["08:00", "08:30"])
        ini_dt = datetime.combine(dt, datetime.strptime(ini, "%H:%M").time())
        s1 = ini_dt + timedelta(minutes=240)
        e2 = s1 + timedelta(minutes=random.choice([60, 75]))
        s2 = e2 + timedelta(minutes=(m - 240))
        recs.append(ExportRecord(
            date=dt.isoformat(),
            check_in=ini,
            check_out=s1.strftime("%H:%M"),
            break_start=e2.strftime("%H:%M"),
            break_end=s2.strftime("%H:%M")
        ))
    return recs

# --- MODELS PARA API ---

class ExportData(BaseModel):
    employee_name: str
    employee_role: str
    month: str
    year: str
    is_campo: bool
    daily_records: List[ExportRecord]
    custom_role: Optional[str] = None
    custom_department: Optional[str] = None
    custom_work_hours: Optional[str] = None
    generate_from_scratch: Optional[bool] = False
    target_hours: Optional[float] = 210.0
    holidays: Optional[List[int]] = None
    estag_rules: Optional[EstagRules] = None

class DeleteUserRequest(BaseModel):
    user_id: str

def init_firebase_admin():
    if firebase_admin is None:
        raise HTTPException(
            status_code=500,
            detail="firebase-admin nao esta instalado no backend. Rode: pip install -r requirements.txt",
        )

    if firebase_admin._apps:
        return

    service_account_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH")
    service_account_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    project_id = os.getenv("FIREBASE_PROJECT_ID", "")
    options = {"projectId": project_id} if project_id else None
    if service_account_json:
        cred = credentials.Certificate(json.loads(service_account_json))
        firebase_admin.initialize_app(cred, options=options)
    elif service_account_path:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred, options=options)
    else:
        firebase_admin.initialize_app(options=options)

def get_firestore_admin():
    init_firebase_admin()
    return firestore.client()

def send_document_push_notification(user_id: str, title: str, body: str, document_id: str):
    """Envia o push aos aparelhos cadastrados pelo colaborador.

    Falhas de push nao impedem a criacao do documento nem a notificacao interna.
    """
    if messaging is None:
        logger.warning("Push de documento ignorado: firebase-admin indisponivel.")
        return

    try:
        db = get_firestore_admin()
        user_ref = db.collection("users").document(user_id)
        user_doc = user_ref.get()
        user_data = user_doc.to_dict() or {} if user_doc.exists else {}
        tokens = [token for token in user_data.get("fcm_tokens", []) if isinstance(token, str) and token]
        if not tokens:
            logger.info("Push de documento sem aparelho cadastrado para o usuario %s", user_id)
            return

        invalid_tokens = []
        for start in range(0, len(tokens), 500):
            batch_tokens = tokens[start:start + 500]
            message = messaging.MulticastMessage(
                tokens=batch_tokens,
                notification=messaging.Notification(title=title, body=body),
                data={"type": "signature_document", "document_id": document_id},
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id="signature_documents",
                        icon="notification_icon",
                        color="#8B0000",
                    ),
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(aps=messaging.Aps(sound="default"))
                ),
            )
            response = messaging.send_each_for_multicast(message)
            for token, item in zip(batch_tokens, response.responses):
                if item.success or item.exception is None:
                    continue
                error_code = getattr(item.exception, "code", "")
                if error_code in {"registration-token-not-registered", "invalid-registration-token"}:
                    invalid_tokens.append(token)

        if invalid_tokens:
            user_ref.update({"fcm_tokens": firestore.ArrayRemove(invalid_tokens)})
    except Exception as exc:
        logger.warning("Falha ao enviar push de documento: %s", exc)

def decode_firestore_value(value: dict):
    if "stringValue" in value:
        return value["stringValue"]
    if "booleanValue" in value:
        return value["booleanValue"]
    if "integerValue" in value:
        return int(value["integerValue"])
    if "doubleValue" in value:
        return float(value["doubleValue"])
    if "timestampValue" in value:
        return value["timestampValue"]
    if "nullValue" in value:
        return None
    if "mapValue" in value:
        fields = value["mapValue"].get("fields", {})
        return {key: decode_firestore_value(item) for key, item in fields.items()}
    if "arrayValue" in value:
        return [
            decode_firestore_value(item)
            for item in value["arrayValue"].get("values", [])
        ]
    return None

async def get_firestore_document_with_user_token(
    collection_name: str,
    document_id: str,
    id_token: str,
) -> Optional[dict]:
    project_id = os.getenv("FIREBASE_PROJECT_ID", "")
    if not project_id:
        raise HTTPException(status_code=503, detail="FIREBASE_PROJECT_ID nao configurado.")

    url = (
        f"https://firestore.googleapis.com/v1/projects/{project_id}"
        f"/databases/(default)/documents/{collection_name}/{document_id}"
    )
    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.get(
            url,
            headers={"Authorization": f"Bearer {id_token}"},
        )
    if response.status_code == 404:
        return None
    if response.status_code < 200 or response.status_code >= 300:
        raise HTTPException(
            status_code=403,
            detail="Nao foi possivel validar as permissoes no Firebase.",
        )

    fields = response.json().get("fields", {})
    return {key: decode_firestore_value(value) for key, value in fields.items()}

async def verify_firebase_user_token(id_token: str) -> str:
    if FIREBASE_WEB_API_KEY:
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                response = await client.post(
                    "https://identitytoolkit.googleapis.com/v1/accounts:lookup",
                    params={"key": FIREBASE_WEB_API_KEY},
                    json={"idToken": id_token},
                )
        except httpx.RequestError as exc:
            raise HTTPException(status_code=502, detail="Falha ao validar a sessao Firebase.") from exc

        users = response.json().get("users", []) if response.is_success else []
        user_uid = users[0].get("localId") if users else None
        if user_uid:
            return user_uid
        raise HTTPException(status_code=401, detail="Token invalido ou expirado.")

    init_firebase_admin()
    try:
        decoded = firebase_auth.verify_id_token(id_token)
        user_uid = decoded.get("uid")
    except Exception as exc:
        logger.warning("Firebase token validation failed: %s: %s", type(exc).__name__, exc)
        raise HTTPException(status_code=401, detail="Token invalido ou expirado.")

    if not user_uid:
        raise HTTPException(status_code=401, detail="Usuario nao autenticado.")
    return user_uid

async def require_authenticated_user(token: HTTPAuthorizationCredentials = Depends(security)):
    user_uid = await verify_firebase_user_token(token.credentials)

    user_data = await get_firestore_document_with_user_token(
        "users",
        user_uid,
        token.credentials,
    )
    if user_data is None:
        raise HTTPException(status_code=403, detail="Perfil do usuario nao encontrado.")

    return {
        "id": user_uid,
        "_id_token": token.credentials,
        **user_data,
    }

async def require_admin_user(user=Depends(require_authenticated_user)):
    if user.get("role") not in ["admin", "manager"]:
        raise HTTPException(status_code=403, detail="Apenas admin ou manager pode executar esta acao.")
    return user

def serialize_firestore_document(document) -> dict:
    data = document.to_dict() or {}
    for key, value in list(data.items()):
        if isinstance(value, datetime):
            data[key] = value.isoformat()
    return {"id": document.id, **data}

def get_zapsign_headers() -> dict:
    if not ZAPSIGN_API_TOKEN or ZAPSIGN_API_TOKEN.startswith("cole-aqui"):
        raise HTTPException(
            status_code=503,
            detail="ZapSign nao configurada. Defina ZAPSIGN_API_TOKEN no backend.",
        )
    return {
        "Authorization": f"Bearer {ZAPSIGN_API_TOKEN}",
        "Content-Type": "application/json",
    }

async def zapsign_request(method: str, path: str, json_data: Optional[dict] = None) -> dict:
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.request(
                method,
                f"{ZAPSIGN_API_BASE_URL}/{path.lstrip('/')}",
                headers=get_zapsign_headers(),
                json=json_data,
            )
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail=f"Falha ao conectar com a ZapSign: {exc}")

    if response.status_code < 200 or response.status_code >= 300:
        try:
            detail = response.json()
        except ValueError:
            detail = response.text
        raise HTTPException(
            status_code=502,
            detail=f"ZapSign recusou a operacao ({response.status_code}): {detail}",
        )

    return response.json()

def zapsign_document_fields(payload: dict) -> dict:
    signers = payload.get("signers") or []
    signer = signers[0] if signers else {}
    signer_token = signer.get("token", "")
    return {
        "zapsign_document_token": payload.get("token", ""),
        "zapsign_signer_token": signer_token,
        "status": payload.get("status", "pending"),
        "signer_status": signer.get("status", "new"),
        "sign_url": f"{ZAPSIGN_APP_URL}/{signer_token}" if signer_token else "",
        "original_file_url": payload.get("original_file") or "",
        "signed_file_url": payload.get("signed_file") or "",
        "signed_at": signer.get("signed_at"),
        "zapsign_last_update_at": payload.get("last_update_at"),
    }

SIGNATURE_DOCUMENT_COLUMNS = """
    id, user_id, user_name, user_email, title, message, original_file_name,
    status, signer_status, zapsign_document_token, zapsign_signer_token,
    sign_url, original_file_url, signed_file_url, signed_at,
    zapsign_last_update_at, error_message, webhook_event,
    created_by_id, created_by_name, created_by_email, created_at, updated_at
"""

def signature_db_connection():
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    return connection

def init_signature_documents_table():
    with signature_db_connection() as connection:
        connection.execute("""
            CREATE TABLE IF NOT EXISTS signature_documents (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                user_name TEXT NOT NULL,
                user_email TEXT NOT NULL,
                title TEXT NOT NULL,
                message TEXT NOT NULL DEFAULT '',
                original_file_name TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'creating',
                signer_status TEXT NOT NULL DEFAULT '',
                zapsign_document_token TEXT NOT NULL DEFAULT '',
                zapsign_signer_token TEXT NOT NULL DEFAULT '',
                sign_url TEXT NOT NULL DEFAULT '',
                original_file_url TEXT NOT NULL DEFAULT '',
                signed_file_url TEXT NOT NULL DEFAULT '',
                signed_at TEXT,
                zapsign_last_update_at TEXT,
                error_message TEXT NOT NULL DEFAULT '',
                webhook_event TEXT NOT NULL DEFAULT '',
                created_by_id TEXT NOT NULL,
                created_by_name TEXT NOT NULL DEFAULT '',
                created_by_email TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        connection.execute("""
            CREATE TABLE IF NOT EXISTS signature_notifications (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                document_id TEXT NOT NULL DEFAULT '',
                is_read INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            )
        """)

def get_signature_document(document_id: str) -> Optional[dict]:
    with signature_db_connection() as connection:
        row = connection.execute(
            f"SELECT {SIGNATURE_DOCUMENT_COLUMNS} FROM signature_documents WHERE id = ?",
            (document_id,),
        ).fetchone()
    return dict(row) if row else None

def update_signature_document(document_id: str, fields: dict):
    allowed_fields = {
        "status", "signer_status", "zapsign_document_token",
        "zapsign_signer_token", "sign_url", "original_file_url",
        "signed_file_url", "signed_at", "zapsign_last_update_at",
        "error_message", "webhook_event", "updated_at",
    }
    values = {key: value for key, value in fields.items() if key in allowed_fields}
    if not values:
        return
    assignments = ", ".join(f"{key} = ?" for key in values)
    with signature_db_connection() as connection:
        connection.execute(
            f"UPDATE signature_documents SET {assignments} WHERE id = ?",
            (*values.values(), document_id),
        )

def find_signature_document_id(document_token: str) -> Optional[str]:
    with signature_db_connection() as connection:
        row = connection.execute(
            "SELECT id FROM signature_documents WHERE zapsign_document_token = ? LIMIT 1",
            (document_token,),
        ).fetchone()
    return row["id"] if row else None

def create_signature_notification(user_id: str, title: str, body: str, document_id: str):
    if not user_id:
        return
    with signature_db_connection() as connection:
        connection.execute(
            """
            INSERT INTO signature_notifications (id, user_id, title, body, document_id, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                secrets.token_urlsafe(16), user_id, title, body, document_id,
                datetime.utcnow().isoformat() + "Z",
            ),
        )

def create_signed_notification_if_needed(document: dict, previous_status: str, current_status: str):
    if previous_status == "signed" or current_status != "signed":
        return
    create_signature_notification(
        document.get("created_by_id", ""),
        "Documento assinado",
        f"{document.get('user_name', 'O colaborador')} assinou \"{document.get('title', 'o documento')}\".",
        document.get("id", ""),
    )

@app.on_event("startup")
def initialize_local_tables():
    init_signature_documents_table()

def delete_query_in_batches(db, query, batch_size: int = 300) -> int:
    deleted = 0
    while True:
        docs = list(query.limit(batch_size).stream())
        if not docs:
            return deleted

        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()
        deleted += len(docs)

def delete_user_cascade(db, user_id: str) -> dict:
    collections_by_user_id = [
        "time_records",
        "adjustment_requests",
        "adjustment_conversations",
    ]
    deleted_counts = {}

    for collection_name in collections_by_user_id:
        count = delete_query_in_batches(
            db,
            db.collection(collection_name).where("user_id", "==", user_id),
        )
        deleted_counts[collection_name] = count

    audit_cleanup_queries = [
        ("time_record_audits", "record_user_id"),
        ("user_audits", "deleted_user_id"),
    ]
    for collection_name, field_name in audit_cleanup_queries:
        count = delete_query_in_batches(
            db,
            db.collection(collection_name).where(field_name, "==", user_id),
        )
        deleted_counts[collection_name] = count

    user_ref = db.collection("users").document(user_id)
    if user_ref.get().exists:
        user_ref.delete()
        deleted_counts["users"] = 1
    else:
        deleted_counts["users"] = 0

    return deleted_counts

# --- LÓGICA EXCEL ---

def generate_excel_file(data: ExportData) -> str:
    type_path = "Excel-Campo" if data.is_campo else "Excel-Administrativos"
    file_name = f"Folha_Ponto_Campo_{data.month}-{data.year}.xlsx" if data.is_campo else f"Folha_Ponto_administrativo_{data.month}-{data.year}.xlsx"
    
    template_path = os.path.join("..", "frontend", "assets", "templates", type_path, data.year, f"{data.month}-{data.year}", file_name)
    if not os.path.exists(template_path):
        template_path = os.path.join("frontend", "assets", "templates", type_path, data.year, f"{data.month}-{data.year}", file_name)
        if not os.path.exists(template_path):
             template_path = os.path.join("ponto-system", "frontend", "assets", "templates", type_path, data.year, f"{data.month}-{data.year}", file_name)
             if not os.path.exists(template_path):
                raise FileNotFoundError(f"Template não encontrado: {file_name}")

    wb = openpyxl.load_workbook(template_path)
    ws = wb.active

    if data.generate_from_scratch:
        data.daily_records = generate_scratch_records(int(data.year), int(data.month), data.target_hours or 210.0)

    ws.cell(row=5, column=3).value = data.employee_name
    is_estagiario = "estagiario" in data.employee_role.lower() or "intern" in data.employee_role.lower()

    if data.custom_role: ws.cell(row=6, column=3).value = data.custom_role
    elif is_estagiario: ws.cell(row=6, column=3).value = "Aux. Administrativo"
    else:
        name_norm = data.employee_name.strip().lower()
        ws.cell(row=6, column=3).value = "Técnico Geral" if (data.is_campo and name_norm.startswith("kelvyn")) else "Aux. Geral"

    ws.cell(row=5, column=11).value = data.custom_work_hours or ("13:30 - 19:30" if is_estagiario else "-")
    ws.cell(row=6, column=9).value = data.custom_department or ("Processamento de Dados" if is_estagiario else "Campo")

    total_bank = {"normal": 0, "extras": 0, "50": 0, "100": 0}

    for d in range(1, 32):
        row_idx = 8 + d
        ws.cell(row=row_idx, column=9).value = f"=IFERROR(MOD(D{row_idx}-C{row_idx},1),0)+IFERROR(MOD(F{row_idx}-E{row_idx},1),0)+IFERROR(MOD(H{row_idx}-G{row_idx},1),0)"
        ws.cell(row=row_idx, column=9).number_format = "[h]:mm"

    holiday_days = set(data.holidays or [])

    for record in data.daily_records:
        day = datetime.fromisoformat(record.date).day
        row_idx = 8 + day
        if record.check_in: ws.cell(row=row_idx, column=3).value = record.check_in
        if record.check_out:
            val_out = record.check_out
            if val_out == "00:00": val_out = "23:59"
            ws.cell(row=row_idx, column=4).value = val_out
        if record.break_start: ws.cell(row=row_idx, column=5).value = record.break_start
        if record.break_end: ws.cell(row=row_idx, column=6).value = record.break_end

        if is_estagiario and record.check_in and record.check_out:
            record_date = datetime.fromisoformat(record.date).date()
            payroll = classify_estag_payroll(record, record_date, holiday_days, data.estag_rules)
            total_bank["normal"] += payroll["normal"]
            total_bank["extras"] += payroll["extras"]
            total_bank["50"] += payroll["50"]
            total_bank["100"] += payroll["100"]

    if is_estagiario:
        ws.cell(row=SUMMARY_ROW_TITLE, column=2).value = "Normais"
        ws.cell(row=SUMMARY_ROW_TITLE, column=3).value = "Extras"
        ws.cell(row=SUMMARY_ROW_TITLE, column=4).value = "50%"
        ws.cell(row=SUMMARY_ROW_TITLE, column=5).value = "100%"
        ws.cell(row=SUMMARY_ROW_HOURS, column=2).value = total_bank["normal"] / 1440.0
        ws.cell(row=SUMMARY_ROW_HOURS, column=3).value = total_bank["extras"] / 1440.0
        ws.cell(row=SUMMARY_ROW_HOURS, column=4).value = total_bank["50"] / 1440.0
        ws.cell(row=SUMMARY_ROW_HOURS, column=5).value = total_bank["100"] / 1440.0
        ws.cell(row=SUMMARY_ROW_VALUE, column=2).value = f"=B42*24*{RATE_NORMAL}"
        ws.cell(row=SUMMARY_ROW_VALUE, column=3).value = f"=C42*24*{RATE_EXTRA}"
        ws.cell(row=SUMMARY_ROW_VALUE, column=4).value = f"=D42*24*{RATE_50}"
        ws.cell(row=SUMMARY_ROW_VALUE, column=5).value = f"=E42*24*{RATE_100}"
        bold = Font(bold=True); thin = Side(style="thin", color="000000"); border = Border(left=thin, right=thin, top=thin, bottom=thin)
        for i in range(2, 6):
            ws.cell(row=SUMMARY_ROW_HOURS, column=i).number_format = "[h]:mm"
            ws.cell(row=SUMMARY_ROW_VALUE, column=i).number_format = '#,##0.00'
            for r in [SUMMARY_ROW_TITLE, SUMMARY_ROW_HOURS, SUMMARY_ROW_VALUE]:
                ws.cell(row=r, column=i).font = bold; ws.cell(row=r, column=i).border = border
        ws.cell(row=SUMMARY_ROW_FINAL, column=2).value = "TOTAL GERAL"
        ws.cell(row=SUMMARY_ROW_FINAL, column=3).value = "=SUM(B43:E43)+500"
        ws.cell(row=SUMMARY_ROW_FINAL, column=3).number_format = '"R$ "#,##0.00'; ws.cell(row=SUMMARY_ROW_FINAL, column=3).font = bold

    for r in range(9, 40):
        for c in range(COL_M, COL_T + 1):
            cell = ws.cell(row=r, column=c)
            if is_estagiario or cell.value == 0:
                cell.value = None

    try: ws.unmerge_cells('I40:J40')
    except: pass
    ws.merge_cells('I40:J40')
    cell_total = ws['I40']; cell_total.value = "=SUM(I9:I39)"; cell_total.number_format = "[h]:mm"
    cell_total.alignment = Alignment(horizontal="center", vertical="center"); cell_total.font = Font(bold=True)

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".xlsx")
    wb.save(tmp.name); wb.close()
    return tmp.name

# --- LOGICA HTML (RELATORIO MENSAL COM ABAS) ---

def is_intern_export(data: ExportData) -> bool:
    role = data.employee_role.lower()
    custom_role = (data.custom_role or "").lower()
    return "estag" in role or "intern" in role or "estag" in custom_role

def excel_download_filename(data: ExportData) -> str:
    suffix = "_estag" if is_intern_export(data) else ""
    return f"Folha_Ponto_{data.employee_name}_{data.month}{suffix}.xlsx"

MONTH_NAMES = {
    1: "Janeiro", 2: "Fevereiro", 3: "Marco", 4: "Abril",
    5: "Maio", 6: "Junho", 7: "Julho", 8: "Agosto",
    9: "Setembro", 10: "Outubro", 11: "Novembro", 12: "Dezembro",
}

WEEKDAY_NAMES = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sab", "Dom"]

HTML_STYLE = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:#f0f2f5;color:#222;font-size:14px}
header{background:#1a3a5c;color:#fff;padding:1rem 1.5rem}
header h1{font-size:1.15rem}
header p{font-size:.8rem;opacity:.78;margin-top:.2rem}
.tabs-wrap{background:#1a3a5c;padding:0 .5rem;display:flex;flex-wrap:wrap;gap:2px;align-items:flex-end;position:sticky;top:0;z-index:10}
.tab-btn{background:rgba(255,255,255,.1);color:#cde;border:none;padding:.45rem .75rem;cursor:pointer;font-size:.78rem;border-radius:4px 4px 0 0;white-space:nowrap;transition:background .15s}
.tab-btn:hover{background:rgba(255,255,255,.22)}
.tab-btn.active{background:#f0f2f5;color:#1a3a5c;font-weight:700}
.tab-btn.consolidado{background:#c07010;color:#fff;margin-left:auto}
.tab-btn.consolidado.active{background:#f0f2f5;color:#c07010}
.badge{display:inline-block;font-size:.62rem;padding:1px 5px;border-radius:3px;margin-left:3px;vertical-align:middle}
.badge.estag{background:#3a7bd5;color:#fff}.badge.rev{background:#c05010;color:#fff}.badge.clt{background:#28724f;color:#fff}
.content{padding:1rem}
.tab-panel{background:#fff;border-radius:6px;padding:1.1rem;box-shadow:0 1px 5px rgba(0,0,0,.1)}
.emp-header{margin-bottom:.6rem}.emp-info h2{font-size:1.2rem;color:#1a3a5c}
.emp-info span{display:inline-block;margin-right:1.2rem;font-size:.85rem;color:#555;margin-top:.25rem}
.data-warn{background:#fff3cd;border:1px solid #f0ad4e;border-left:4px solid #e67e00;border-radius:4px;padding:.55rem .8rem;font-size:.82rem;color:#6d4400;margin-bottom:.7rem}
.summary-grid{display:flex;flex-wrap:wrap;gap:.5rem;margin:.6rem 0 .8rem}
.s-card{background:#f4f6fa;border-radius:5px;padding:.45rem .8rem;min-width:100px;text-align:center;border-top:3px solid #cbd3e8}
.s-card span{display:block;font-size:.68rem;color:#666}.s-card strong{font-size:1rem;color:#1a3a5c}
.s-card.normal{border-color:#3a7bd5}.s-card.he50{border-color:#e89020}.s-card.he100{border-color:#d04020}
.s-card.noc{border-color:#5040a0}.s-card.noc2{border-color:#8060d0}.s-card.dom{border-color:#c02060}.s-card.fer{border-color:#e06010}.s-card.dsr{border-color:#b06000}
.payroll-notice{background:#f0f6ff;border:1px solid #b8d4f8;border-left:4px solid #1a5fc8;border-radius:4px;padding:.6rem 1rem;margin:.6rem 0 .8rem}
.payroll-notice.ok{background:#eafaf1;border-color:#a3d9a5;border-left-color:#27ae60;color:#1a5c2a}
.payroll-notice.estag-note{background:#fdf4e7;border-color:#f5c980;border-left-color:#c07010;color:#704000}
.pn-title{font-weight:700;font-size:.85rem;margin-bottom:.3rem;color:#1a3a5c}
.payroll-notice.ok .pn-title,.payroll-notice.estag-note .pn-title{color:inherit}
.pn-list{padding-left:1.2rem;margin:0;font-size:.82rem;line-height:1.7}
.pi-lbl{display:inline-block;font-size:.65rem;font-weight:700;padding:1px 6px;border-radius:3px;margin-right:4px;vertical-align:middle}
.pi-lbl.he50{background:#fde9c0;color:#7a4800}.pi-lbl.he100{background:#fdd;color:#900}.pi-lbl.noc{background:#ede;color:#408}.pi-lbl.dom{background:#fcd;color:#900}.pi-lbl.fer{background:#ffe0b2;color:#7a3600}.pi-lbl.dsr{background:#fda;color:#640}
.section-title{font-size:.92rem;font-weight:700;color:#1a3a5c;background:#e8eef8;border-left:4px solid #1a3a5c;padding:.35rem .7rem;border-radius:0 4px 4px 0;margin-bottom:.4rem}
.legend{font-size:.78rem;color:#555;margin-bottom:.6rem;line-height:1.6}
.table-wrap{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:.82rem}
th{background:#1a3a5c;color:#fff;padding:.4rem .5rem;text-align:center;white-space:nowrap}
td{padding:.28rem .45rem;text-align:center;border-bottom:1px solid #eee;white-space:nowrap}
tr:hover td{background:#f5f8ff}tr.sabado td{background:#fffbe6}tr.domingo td{background:#fff0f4}tr.feriado td{background:#fff4e0}tr.estag-row td{background:#f0f8ff}
tr.totals td{background:#eef2fa;font-weight:600}tr.grand-total td{background:#1a3a5c;color:#fff}
.soma{font-weight:700;color:#1a3a5c}.hn{color:#2255aa}.he50{color:#b06000;font-weight:600}.he100{color:#c02000;font-weight:600}.noc{color:#5040a0}.dom{color:#c02060}.fer{color:#c05000}.dsr-col{color:#7a4000;font-weight:600}
.hora-zero{color:#ccc}.num{color:#444}.na{color:#aaa;font-style:italic;font-size:.75rem}.nil{color:#bbb}.centro{text-align:center}.warn-ico{color:#e67e00;font-style:normal}
.flags{text-align:left;white-space:normal;min-width:80px}.flag{display:inline-block;font-size:.63rem;padding:1px 5px;border-radius:3px;margin:1px 2px;font-weight:700;white-space:nowrap}
.flag.dom{background:#fcd;color:#900}.flag.fer{background:#ffe0b2;color:#7a3600}.flag.dsr{background:#fda;color:#640}.flag.noc{background:#dce;color:#408;cursor:help}.flag.warn{background:#fff3cd;color:#7a4400;border:1px solid #f0ad4e}
.tag{display:inline-block;font-size:.63rem;font-weight:700;padding:1px 5px;border-radius:3px;margin:1px}.tag.he50{background:#fde9c0;color:#7a4800}.tag.he100{background:#fdd;color:#900}.tag.noc{background:#ede;color:#408}.tag.dom{background:#fcd;color:#900}.tag.fer{background:#ffe0b2;color:#7a3600}
.fonte{font-size:.72rem;color:#888;margin-top:.7rem;text-align:right}
@media print{.tabs-wrap{display:none}.tab-panel{display:block!important;page-break-after:always}body{background:#fff}.content{padding:0}.tab-panel{box-shadow:none;border-radius:0}}
"""

def esc(value) -> str:
    return html.escape("" if value is None else str(value))

def tab_id(name: str, idx: int, month: str, year: str, is_estagiario: bool = False) -> str:
    base = re.sub(r"[^A-Za-z0-9_]+", "_", name.strip())
    suffix = "_estag" if is_estagiario else ""
    tail = "" if idx == 0 else f"_{idx}"
    return f"Folha_Ponto_{base}_{month}-{year}{suffix}{tail}"

def abbreviated_name(name: str) -> str:
    parts = [part for part in name.strip().split() if part]
    if len(parts) <= 1:
        return name or "Colaborador"
    if len(parts) == 2:
        return f"{parts[0]} {parts[1][0]}."
    middle = " ".join(f"{part[0]}." for part in parts[1:-1] if part)
    return f"{parts[0]} {middle} {parts[-1]}".strip()

def hours_to_minutes(value) -> int:
    if value is None:
        return 0
    try:
        return int(round(float(value) * 60))
    except Exception:
        return 0

def fmt_minutes(minutes: int, dash: bool = True) -> str:
    minutes = int(round(minutes))
    if minutes <= 0 and dash:
        return "-"
    return f"{minutes // 60:02d}:{minutes % 60:02d}"

def record_total_minutes(record: ExportRecord) -> int:
    if record.total_hours is not None:
        return hours_to_minutes(record.total_hours)

    total = 0
    pairs = [
        (record.check_in, record.check_out),
        (record.break_start, record.break_end),
        (record.entry_3, record.exit_3),
    ]
    for start, end in pairs:
        if start and end:
            total += minutes_between_str(start, end)
    return total

def classify_html_day(record: ExportRecord, is_estagiario: bool, current_date: date, is_holiday: bool = False, rules: Optional[EstagRules] = None) -> dict:
    total = record_total_minutes(record)
    if is_estagiario:
        payroll = classify_estag_payroll(record, current_date, {current_date.day} if is_holiday else set(), rules)
        return {
            "total": total,
            "normal": payroll["normal"],
            "extra_contract": payroll["extras"],
            "he50": payroll["50"],
            "he100": payroll["100"],
            "noc_real": 0,
            "noc_ficto": 0,
        }

    normal = hours_to_minutes(record.regular_hours)
    he50 = hours_to_minutes(record.extra_50)
    he100 = hours_to_minutes(record.extra_100)

    if normal or he50 or he100:
        return {"total": total or normal + he50 + he100, "normal": normal, "extra_contract": 0, "he50": he50, "he100": he100, "noc_real": 0, "noc_ficto": 0}

    if current_date.weekday() == 6 or is_holiday:
        return {"total": total, "normal": 0, "extra_contract": 0, "he50": 0, "he100": total, "noc_real": 0, "noc_ficto": 0}

    normal = min(total, 480)
    he50 = min(max(total - 480, 0), 120)
    he100 = max(total - 600, 0)
    return {"total": total, "normal": normal, "extra_contract": 0, "he50": he50, "he100": he100, "noc_real": 0, "noc_ficto": 0}

def employee_role(data: ExportData, is_estagiario: bool) -> str:
    if data.custom_role:
        return data.custom_role
    if is_estagiario:
        return "Aux. Administrativo"
    return data.employee_role if data.employee_role not in ["employee", "manager", "admin"] else "Aux. Geral"

def employee_department(data: ExportData, is_estagiario: bool) -> str:
    if data.custom_department:
        return data.custom_department
    return "Processamento de Dados" if is_estagiario else "Campo"

def build_employee_html(data: ExportData, panel_id: str, visible: bool) -> tuple[str, dict]:
    year = int(data.year)
    month = int(data.month)
    is_estagiario = "estag" in data.employee_role.lower() or "intern" in data.employee_role.lower()
    role = employee_role(data, is_estagiario)
    department = employee_department(data, is_estagiario)

    if data.generate_from_scratch:
        data.daily_records = generate_scratch_records(year, month, data.target_hours or 210.0)

    holiday_days = set(data.holidays or [])
    records_by_day = {datetime.fromisoformat(r.date).day: r for r in data.daily_records}
    totals = {"days": 0, "total": 0, "normal": 0, "extra_contract": 0, "he50": 0, "he100": 0, "noc_real": 0, "noc_ficto": 0}
    rows = []

    for day in range(1, monthrange(year, month)[1] + 1):
        current_date = date(year, month, day)
        record = records_by_day.get(day)
        classes = []
        is_holiday = day in holiday_days
        if is_holiday:
            classes.append("feriado")
        elif current_date.weekday() == 5:
            classes.append("sabado")
        elif current_date.weekday() == 6:
            classes.append("domingo")
        if is_estagiario:
            classes.append("estag-row")

        vals = {"total": 0, "normal": 0, "extra_contract": 0, "he50": 0, "he100": 0, "noc_real": 0, "noc_ficto": 0}
        if record:
            vals = classify_html_day(record, is_estagiario, current_date, is_holiday, data.estag_rules)
            if vals["total"] > 0:
                totals["days"] += 1
            for key in ["total", "normal", "extra_contract", "he50", "he100", "noc_real", "noc_ficto"]:
                totals[key] += vals[key]

        flags = []
        if current_date.weekday() == 6:
            flags.append('<span class="flag dom">DOM</span>')
            if vals["total"] > 0:
                flags.append('<span class="flag dsr">DSR</span>')
        if is_holiday:
            flags.append('<span class="flag fer">FERIADO +100%</span>')
            if vals["total"] > 0:
                flags.append('<span class="flag dsr">100%</span>')
        if vals["noc_ficto"] > 0:
            flags.append(f'<span class="flag noc" title="Real: {fmt_minutes(vals["noc_real"])}">AN {fmt_minutes(vals["noc_ficto"])}</span>')

        rows.append(f"""
<tr class="{' '.join(classes)}">
  <td>{day}</td><td>{WEEKDAY_NAMES[current_date.weekday()]}</td>
  <td>{esc(record.check_in if record else '')}</td><td>{esc(record.check_out if record else '')}</td>
  <td>{esc(record.break_start if record else '')}</td><td>{esc(record.break_end if record else '')}</td>
  <td>{esc(record.entry_3 if record else '')}</td><td>{esc(record.exit_3 if record else '')}</td>
  <td class="soma {'hora-zero' if vals['total'] <= 0 else ''}">{fmt_minutes(vals['total'])}</td>
  <td class="hn">{fmt_minutes(vals['normal'], dash=False) if vals['normal'] else ''}</td>
  <td class="he50">{fmt_minutes(vals['he50'], dash=False) if vals['he50'] else ''}</td>
  <td class="he100">{fmt_minutes(vals['he100'], dash=False) if vals['he100'] else ''}</td>
  <td class="flags">{''.join(flags)}</td>
</tr>""")

    notice = (
        f"""<div class="payroll-notice estag-note"><div class="pn-title">Estagiario - regras aplicadas</div><ul class="pn-list">
<li><span class="pi-lbl he50">Sabado 50%</span> <strong>{fmt_minutes(totals['he50'])}</strong> - horas de sabado entre 06h e 22h</li>
<li><span class="pi-lbl he100">100%</span> <strong>{fmt_minutes(totals['he100'])}</strong> - domingo, feriado e horario noturno 22h-05h</li>
<li><span class="pi-lbl he50">Extras contrato</span> <strong>{fmt_minutes(totals['extra_contract'])}</strong> - excedente de jornada em dia normal</li>
</ul></div>"""
        if is_estagiario
        else f"""<div class="payroll-notice"><div class="pn-title">Lancamentos na Folha de Pagamento</div><ul class="pn-list">
<li><span class="pi-lbl he50">HE 50%</span> <strong>{fmt_minutes(totals['he50'])}</strong> - horas extras entre 8h e 10h/dia</li>
<li><span class="pi-lbl he100">HE 100%</span> <strong>{fmt_minutes(totals['he100'])}</strong> - horas extras acima de 10h/dia e domingos/DSR</li>
<li><span class="pi-lbl noc">Ad. Noturno</span> <strong>{fmt_minutes(totals['noc_ficto'])}</strong> h ficto</li>
</ul></div>"""
    )

    panel = f"""
<div class="tab-panel" id="panel-{panel_id}" style="display:{'block' if visible else 'none'}">
  <div class="emp-header"><div class="emp-info">
    <h2>{esc(data.employee_name)}{'<span class="badge estag">Estag.</span>' if is_estagiario else ''}</h2>
    <span>Funcao: <strong>{esc(role)}</strong></span>
    <span>Departamento: <strong>{esc(department)}</strong></span>
  </div></div>
  <div class="summary-grid">
    <div class="s-card"><span>Total Horas</span><strong>{fmt_minutes(totals['total'])}</strong></div>
    <div class="s-card normal"><span>Horas Normais</span><strong>{fmt_minutes(totals['normal'])}</strong></div>
    <div class="s-card he50"><span>{'Sabado 50%' if is_estagiario else 'HE 50% (8h-10h)'}</span><strong>{fmt_minutes(totals['he50'])}</strong></div>
    <div class="s-card he100"><span>{'Dom/Fer/Not. 100%' if is_estagiario else 'HE 100% (&gt;10h)'}</span><strong>{fmt_minutes(totals['he100'])}</strong></div>
    <div class="s-card noc"><span>Ad. Not. real</span><strong>{fmt_minutes(totals['noc_real'])}</strong></div>
    <div class="s-card noc2"><span>AN ficto (x8/7)</span><strong>{fmt_minutes(totals['noc_ficto'])}</strong></div>
  </div>
  {notice}
  <div class="legend">
    <span class="flag fer">FERIADO</span> Feriado trabalhado (+100%) &nbsp;
    <span class="flag dom">DOM</span> Domingo (+100%) &nbsp;
    <span class="flag dsr">DSR</span> Horas no DSR (HE 100%) &nbsp;
    <span class="flag noc">AN hh:mm</span> Ad. Noturno ficto (x8/7, 22h-05h)
  </div>
  <div class="table-wrap"><table>
    <thead><tr>
      <th>Dia</th><th></th><th>Ent.</th><th>Sai.</th><th>Ent.</th><th>Sai.</th><th>Ent.</th><th>Sai.</th>
      <th>Total</th><th title="Horas normais ate 8h/dia">HN</th><th title="Horas 50%">HE 50%</th><th title="Horas 100%">HE 100%</th><th>Obs.</th>
    </tr></thead>
    <tbody>{''.join(rows)}</tbody>
    <tfoot><tr class="totals"><td colspan="8">Totais</td><td class="soma">{fmt_minutes(totals['total'])}</td><td class="hn">{fmt_minutes(totals['normal'])}</td><td class="he50">{fmt_minutes(totals['he50'])}</td><td class="he100">{fmt_minutes(totals['he100'])}</td><td></td></tr></tfoot>
  </table></div>
  <div class="fonte">Arquivo: {esc(excel_download_filename(data))}</div>
</div>"""

    summary = {**totals, "name": data.employee_name, "role": role, "department": department, "is_estagiario": is_estagiario}
    return panel, summary

def build_consolidated_html(summaries: List[dict], month_label: str) -> str:
    rows = []
    grand = {"days": 0, "total": 0, "normal": 0, "he50": 0, "he100": 0, "noc_ficto": 0}
    for summary in summaries:
        for key in grand:
            grand[key] += summary[key]
        estag = summary["is_estagiario"]
        rows.append(f"""
<tr class="{'estag-row' if estag else ''}">
  <td>{esc(summary['name'])}{'<span class="badge estag">Estag.</span>' if estag else ''}</td>
  <td class="centro"><span class="badge {'estag' if estag else 'clt'}">{'Estag.' if estag else 'CLT'}</span></td>
  <td>{esc(summary['role'])}</td><td>{esc(summary['department'])}</td>
  <td class="num">{summary['days']}</td>
  <td class="hn">{fmt_minutes(summary['normal'])}</td>
  <td class="he50">{fmt_minutes(summary['he50'])}</td>
  <td class="he100">{fmt_minutes(summary['he100'])}</td>
  <td class="noc">{fmt_minutes(summary['noc_ficto'])}</td>
  <td class="soma">{fmt_minutes(summary['total'])}</td>
</tr>""")

    return f"""
<div class="tab-panel" id="panel-consolidado" style="display:none">
  <h2>Consolidado - {esc(month_label)}</h2>
  <div class="section-title">Resumo de Apuracao</div>
  <div class="legend" style="margin-bottom:.5rem">
    <strong>HN</strong>=Horas normais &nbsp;|&nbsp;
    <strong>HE 50%</strong>=Extras 8h-10h / sabado estagiario &nbsp;|&nbsp;
    <strong>HE 100%</strong>=Extras &gt;10h + domingos + feriados + noturno estagiario &nbsp;|&nbsp;
    <strong>AN ficto</strong>=Ad.Noturno hora ficta &nbsp;|&nbsp;
    HN + HE50% + HE100% = Total Horas
  </div>
  <div class="table-wrap"><table>
    <thead><tr><th>Empregado</th><th>Tipo</th><th>Funcao</th><th>Departamento</th><th>Dias</th><th class="hn">HN</th><th class="he50">HE 50%</th><th class="he100">HE 100%</th><th class="noc">AN ficto</th><th class="soma">Total</th></tr></thead>
    <tbody>{''.join(rows)}</tbody>
    <tfoot><tr class="grand-total"><td colspan="4">TOTAL GERAL</td><td>{grand['days']}</td><td class="hn">{fmt_minutes(grand['normal'])}</td><td class="he50">{fmt_minutes(grand['he50'])}</td><td class="he100">{fmt_minutes(grand['he100'])}</td><td class="noc">{fmt_minutes(grand['noc_ficto'])}</td><td class="soma">{fmt_minutes(grand['total'])}</td></tr></tfoot>
  </table></div>
</div>"""

def generate_batch_html_file(data_list: List[ExportData]) -> str:
    if not data_list:
        raise ValueError("Nenhum colaborador para exportar.")

    first = data_list[0]
    month_num = int(first.month)
    month_label = f"{MONTH_NAMES.get(month_num, first.month)}/{first.year}"
    tabs = []
    panels = []
    summaries = []

    for idx, data in enumerate(data_list):
        is_estagiario = "estag" in data.employee_role.lower() or "intern" in data.employee_role.lower()
        panel_id = tab_id(data.employee_name, idx, data.month, data.year, is_estagiario)
        tabs.append(
            f"""<button class="tab-btn {'active' if idx == 0 else ''}" onclick="showTab('{panel_id}')" id="btn-{panel_id}">{esc(abbreviated_name(data.employee_name))}{'<span class="badge estag">Estag.</span>' if is_estagiario else ''}</button>"""
        )
        panel, summary = build_employee_html(data, panel_id, idx == 0)
        panels.append(panel)
        summaries.append(summary)

    tabs.append("""<button class="tab-btn consolidado" onclick="showTab('consolidado')" id="btn-consolidado">&#9776; Consolidado</button>""")
    panels.append(build_consolidated_html(summaries, month_label))

    content = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Folhas de Ponto - VM Engenharia - {esc(month_label)}</title>
<style>{HTML_STYLE}</style>
</head>
<body>
<header>
  <h1>VM Engenharia de Infraestruturas Ltda - CNPJ: 53.655.381/0001-03</h1>
  <p>Folhas de Ponto - {esc(month_label)} - gerado em {datetime.now().strftime('%d/%m/%Y %H:%M')}</p>
</header>
<div class="legend" style="padding:.7rem 1rem;background:#fff;border-bottom:1px solid #dde">
  HN <=8h/dia &nbsp;|&nbsp; HE 50% &nbsp;|&nbsp; HE 100% &nbsp;|&nbsp;
  Ad. Noturno 22h-05h &nbsp;|&nbsp; Dom.+Feriado = +100%
</div>
<div class="tabs-wrap">{''.join(tabs)}</div>
<div class="content">{''.join(panels)}</div>
<script>
function showTab(id){{
  document.querySelectorAll('.tab-panel').forEach(p=>p.style.display='none');
  document.querySelectorAll('.tab-btn').forEach(b=>b.classList.remove('active'));
  document.getElementById('panel-'+id).style.display='block';
  document.getElementById('btn-'+id).classList.add('active');
}}
</script>
</body>
</html>"""

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".html", mode="w", encoding="utf-8")
    tmp.write(content)
    tmp.close()
    return tmp.name

@app.post("/export-excel")
async def export_excel(data: ExportData):
    try:
        file_path = generate_excel_file(data)
        return FileResponse(file_path, filename=excel_download_filename(data), media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/export-batch")
async def export_batch(data_list: List[ExportData]):
    try:
        temp_dir = tempfile.mkdtemp()
        zip_path = os.path.join(temp_dir, "folhas_ponto.zip")
        with zipfile.ZipFile(zip_path, 'w') as zipf:
            for data in data_list:
                file_path = generate_excel_file(data)
                zipf.write(file_path, arcname=excel_download_filename(data))
                os.unlink(file_path)
        return FileResponse(zip_path, filename="Folhas_Ponto_Lote.zip", media_type="application/zip")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/export-batch-html")
async def export_batch_html(data_list: List[ExportData]):
    try:
        file_path = generate_batch_html_file(data_list)
        first = data_list[0]
        return FileResponse(
            file_path,
            filename=f"Folhas_Ponto_VM_{first.month}-{first.year}.html",
            media_type="text/html; charset=utf-8",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/send-assistant-message")
async def send_assistant_message(
    employee_name: str = Form(...),
    employee_email: str = Form(...),
    message: str = Form(...),
    audio: Optional[UploadFile] = File(None)
):
    try:
        body = f"""
        Solicitação de Ajuste de Ponto - Assistente VMac

        Colaborador: {employee_name}
        E-mail: {employee_email}
        Data/Hora: {datetime.now().strftime('%d/%m/%Y %H:%M')}

        Mensagem:
        {message}
        """

        message_schema = MessageSchema(
            subject=f"Ajuste de Ponto - {employee_name}",
            recipients=["vmac.rh.01@gmail.com"],
            body=body,
            subtype=MessageType.plain
        )

        if audio:
            # Salvar áudio temporariamente para anexar
            temp = tempfile.NamedTemporaryFile(delete=False, suffix=".m4a")
            content = await audio.read()
            temp.write(content)
            temp.close()
            message_schema.attachments = [temp.name]

        fm = FastMail(conf)
        await fm.send_message(message_schema)

        if audio:
            os.unlink(temp.name)

        return {"status": "success", "message": "E-mail enviado com sucesso"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao enviar e-mail: {str(e)}")

@app.post("/admin/signature-documents")
async def create_signature_document(
    target_user_id: str = Form(...),
    target_user_name: str = Form(...),
    target_user_email: str = Form(...),
    local_document_id: str = Form(...),
    title: str = Form(...),
    message: str = Form(""),
    pdf: UploadFile = File(...),
    admin=Depends(require_admin_user),
):
    if not title.strip():
        raise HTTPException(status_code=400, detail="Informe o titulo do documento.")

    file_name = pdf.filename or "documento.pdf"
    if not file_name.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Envie um arquivo PDF.")

    pdf_bytes = await pdf.read()
    if not pdf_bytes or not pdf_bytes.startswith(b"%PDF"):
        raise HTTPException(status_code=400, detail="O arquivo enviado nao e um PDF valido.")
    if len(pdf_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="O PDF deve ter no maximo 10 MB.")

    target_name = target_user_name.strip()
    target_email = target_user_email.strip()
    if not target_name:
        raise HTTPException(status_code=400, detail="Informe o nome do colaborador.")
    if not target_email:
        raise HTTPException(status_code=400, detail="O colaborador precisa ter um e-mail cadastrado.")

    now = datetime.utcnow().isoformat() + "Z"
    with signature_db_connection() as connection:
        connection.execute(
            """
            INSERT INTO signature_documents (
                id, user_id, user_name, user_email, title, message,
                original_file_name, status, created_by_id, created_by_name,
                created_by_email, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                local_document_id, target_user_id, target_name, target_email,
                title.strip(), message.strip(), file_name, "creating",
                admin["id"], admin.get("name", ""), admin.get("email", ""),
                now, now,
            ),
        )

    payload = {
        "name": title.strip()[:255],
        "base64_pdf": base64.b64encode(pdf_bytes).decode("ascii"),
        "lang": "pt-br",
        "external_id": local_document_id,
        "folder_path": "/Ponto-VMac/",
        "disable_signer_emails": False,
        "allow_refuse_signature": True,
        "signers": [{
            "name": target_name,
            "email": target_email,
            "auth_mode": "assinaturaTela-tokenEmail",
            "send_automatic_email": True,
            "lock_name": True,
            "lock_email": True,
            "external_id": target_user_id,
        }],
    }

    try:
        result = await zapsign_request("POST", "/docs/", payload)
        update_signature_document(local_document_id, {
            **zapsign_document_fields(result),
            "updated_at": datetime.utcnow().isoformat() + "Z",
        })
    except HTTPException as exc:
        update_signature_document(local_document_id, {
            "status": "error",
            "error_message": str(exc.detail),
            "updated_at": datetime.utcnow().isoformat() + "Z",
        })
        raise

    document = get_signature_document(local_document_id)
    create_signature_notification(
        target_user_id,
        "Documento aguardando assinatura",
        f"RH enviou \"{title.strip()}\" para sua assinatura.",
        local_document_id,
    )
    send_document_push_notification(
        target_user_id,
        "Documento aguardando assinatura",
        f"RH enviou \"{title.strip()}\" para sua assinatura.",
        local_document_id,
    )
    return document

@app.get("/signature-notifications")
async def list_signature_notifications(user=Depends(require_authenticated_user)):
    with signature_db_connection() as connection:
        rows = connection.execute(
            """
            SELECT id, title, body, document_id, is_read, created_at
            FROM signature_notifications
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT 30
            """,
            (user["id"],),
        ).fetchall()
    return [dict(row) for row in rows]

@app.post("/signature-notifications/read")
async def mark_signature_notifications_read(user=Depends(require_authenticated_user)):
    with signature_db_connection() as connection:
        connection.execute(
            "UPDATE signature_notifications SET is_read = 1 WHERE user_id = ? AND is_read = 0",
            (user["id"],),
        )
    return {"status": "success"}

@app.get("/signature-documents")
async def list_my_signature_documents(user=Depends(require_authenticated_user)):
    with signature_db_connection() as connection:
        rows = connection.execute(
            f"""
            SELECT {SIGNATURE_DOCUMENT_COLUMNS}
            FROM signature_documents
            WHERE user_id = ?
            ORDER BY created_at DESC
            """,
            (user["id"],),
        ).fetchall()
    return [dict(row) for row in rows]

@app.get("/admin/signature-documents")
async def list_all_signature_documents(admin=Depends(require_admin_user)):
    with signature_db_connection() as connection:
        rows = connection.execute(
            f"""
            SELECT {SIGNATURE_DOCUMENT_COLUMNS}
            FROM signature_documents
            ORDER BY created_at DESC
            """
        ).fetchall()
    return [dict(row) for row in rows]

@app.post("/signature-documents/{document_id}/refresh")
async def refresh_signature_document(
    document_id: str,
    user=Depends(require_authenticated_user),
):
    data = get_signature_document(document_id)
    if data is None:
        raise HTTPException(status_code=404, detail="Documento nao encontrado.")

    is_admin = user.get("role") in ["admin", "manager"]
    if data.get("user_id") != user["id"] and not is_admin:
        raise HTTPException(status_code=403, detail="Sem acesso a este documento.")

    document_token = data.get("zapsign_document_token")
    if not document_token:
        raise HTTPException(status_code=409, detail="Documento ainda nao foi criado na ZapSign.")

    result = await zapsign_request("GET", f"/docs/{document_token}/")
    previous_status = data.get("status", "")
    update_signature_document(document_id, {
        **zapsign_document_fields(result),
        "updated_at": datetime.utcnow().isoformat() + "Z",
    })
    updated_document = get_signature_document(document_id)
    create_signed_notification_if_needed(
        updated_document, previous_status, updated_document.get("status", ""),
    )
    return updated_document

@app.post("/zapsign/webhook")
async def zapsign_webhook(request: Request):
    if ZAPSIGN_WEBHOOK_SECRET:
        supplied_secret = (
            request.query_params.get("secret")
            or request.headers.get("X-Webhook-Secret")
        )
        if supplied_secret != ZAPSIGN_WEBHOOK_SECRET:
            raise HTTPException(status_code=401, detail="Webhook nao autorizado.")

    payload = await request.json()
    external_id = str(payload.get("external_id") or "")
    document_token = str(payload.get("token") or "")
    document_id = external_id if external_id and get_signature_document(external_id) else None
    if document_id is None and document_token:
        document_id = find_signature_document_id(document_token)

    if document_id is None:
        return {"status": "ignored", "reason": "document_not_found"}

    document = get_signature_document(document_id)
    previous_status = document.get("status", "") if document else ""
    update_signature_document(document_id, {
        **zapsign_document_fields(payload),
        "webhook_event": payload.get("event_type") or payload.get("event") or "",
        "updated_at": datetime.utcnow().isoformat() + "Z",
    })
    updated_document = get_signature_document(document_id)
    create_signed_notification_if_needed(
        updated_document, previous_status, updated_document.get("status", ""),
    )
    return {"status": "success"}

@app.delete("/admin/users/{user_id}")
async def delete_user_admin_endpoint(
    user_id: str,
    admin=Depends(require_admin_user),
):
    if admin["id"] == user_id:
        raise HTTPException(status_code=400, detail="Voce nao pode excluir a propria conta.")

    db = get_firestore_admin()
    target_doc = db.collection("users").document(user_id).get()
    target_data = target_doc.to_dict() if target_doc.exists else {}

    try:
        firebase_auth.delete_user(user_id)
        auth_deleted = True
    except firebase_auth.UserNotFoundError:
        auth_deleted = False
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Erro ao excluir usuario do Authentication: {str(e)}")

    try:
        deleted_counts = delete_user_cascade(db, user_id)
        db.collection("system_audits").document().set({
            "action": "delete_user_cascade",
            "deleted_user_id": user_id,
            "deleted_user_email": target_data.get("email"),
            "deleted_user_name": target_data.get("name"),
            "admin_id": admin["id"],
            "admin_name": admin.get("name", ""),
            "admin_email": admin.get("email", ""),
            "auth_deleted": auth_deleted,
            "deleted_counts": deleted_counts,
            "created_at": firestore.SERVER_TIMESTAMP,
        })
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Auth excluido, mas houve erro ao limpar Firestore: {str(e)}")

    return {
        "status": "success",
        "auth_deleted": auth_deleted,
        "deleted_counts": deleted_counts,
    }

# --- DATABASE SETUP ---
SQLALCHEMY_DATABASE_URL = "sqlite:///./ponto.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=True)
