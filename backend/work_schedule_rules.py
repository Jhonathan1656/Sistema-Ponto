from datetime import date, datetime
from zoneinfo import ZoneInfo


DEFAULT_INTERN_WORK_SCHEDULE = {
    "shift_start": "13:30",
    "shift_end": "19:30",
    "start_allowed_from": "13:25",
    "start_allowed_until": "19:25",
    "overtime_prompt_after": "19:35",
    "timezone": "America/Sao_Paulo",
}


def validate_work_schedule(raw: dict | None) -> dict:
    schedule = {**DEFAULT_INTERN_WORK_SCHEDULE, **(raw or {})}
    time_fields = (
        "shift_start",
        "shift_end",
        "start_allowed_from",
        "start_allowed_until",
        "overtime_prompt_after",
    )
    for field in time_fields:
        value = str(schedule.get(field, "")).strip()
        try:
            parsed = datetime.strptime(value, "%H:%M")
        except ValueError as exc:
            raise ValueError(f"Horario invalido em {field}. Use HH:mm.") from exc
        # strptime aceita "9:30", mas as comparacoes abaixo sao de texto e
        # "9:30" > "13:30". Com zero a esquerda texto e horario batem.
        schedule[field] = parsed.strftime("%H:%M")

    if schedule["start_allowed_from"] > schedule["start_allowed_until"]:
        raise ValueError("A janela de entrada inicial e final e invalida.")
    if schedule["shift_start"] > schedule["shift_end"]:
        raise ValueError("O inicio do turno deve ser anterior ao fim.")
    if schedule["overtime_prompt_after"] < schedule["shift_end"]:
        raise ValueError("O aviso de hora extra nao pode ser anterior ao fim do turno.")

    timezone_name = str(schedule.get("timezone") or "America/Sao_Paulo").strip()
    try:
        ZoneInfo(timezone_name)
    except Exception as exc:
        raise ValueError("Fuso horario invalido.") from exc
    schedule["timezone"] = timezone_name
    return schedule


def time_on_day(day: date, hhmm: str, timezone_name: str) -> datetime:
    parsed = datetime.strptime(hhmm, "%H:%M").time()
    return datetime.combine(day, parsed, tzinfo=ZoneInfo(timezone_name))


def is_start_within_schedule(attempted: datetime, schedule: dict) -> bool:
    # Estagiarios trabalham de segunda (0) a sexta (4). Qualquer entrada no
    # fim de semana depende de liberacao, mesmo dentro da janela de horas.
    if attempted.weekday() > 4:
        return False
    lower = time_on_day(
        attempted.date(), schedule["start_allowed_from"], schedule["timezone"]
    )
    upper = time_on_day(
        attempted.date(), schedule["start_allowed_until"], schedule["timezone"]
    )
    return lower <= attempted <= upper
