"""Historial de pruebas en SQLite."""

import os
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from .schemas import AudiometryResult, SessionInfo

DEFAULT_DB = Path(__file__).resolve().parent.parent / "data" / "audiometria.db"


def _db_path() -> Path:
    return Path(os.environ.get("AUDIOMETRIA_DB", DEFAULT_DB))


def _connect() -> sqlite3.Connection:
    path = _db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.execute(
        """CREATE TABLE IF NOT EXISTS sessions (
               id TEXT PRIMARY KEY,
               created_at TEXT NOT NULL,
               patient_name TEXT NOT NULL,
               performed_at TEXT NOT NULL,
               payload TEXT NOT NULL
           )"""
    )
    return conn


def save(result: AudiometryResult) -> str:
    session_id = uuid.uuid4().hex
    with closing(_connect()) as conn, conn:
        conn.execute(
            "INSERT INTO sessions VALUES (?, ?, ?, ?, ?)",
            (
                session_id,
                datetime.now(timezone.utc).isoformat(),
                result.patient.name,
                result.performed_at.isoformat(),
                result.model_dump_json(),
            ),
        )
    return session_id


def get(session_id: str) -> Optional[AudiometryResult]:
    with closing(_connect()) as conn:
        row = conn.execute("SELECT payload FROM sessions WHERE id = ?", (session_id,)).fetchone()
    return AudiometryResult.model_validate_json(row[0]) if row else None


def list_sessions(limit: int = 100) -> list[SessionInfo]:
    with closing(_connect()) as conn:
        rows = conn.execute(
            "SELECT id, created_at, patient_name, performed_at FROM sessions "
            "ORDER BY created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return [
        SessionInfo(id=r[0], created_at=r[1], patient_name=r[2], performed_at=r[3]) for r in rows
    ]


def delete(session_id: str) -> bool:
    with closing(_connect()) as conn, conn:
        return conn.execute("DELETE FROM sessions WHERE id = ?", (session_id,)).rowcount > 0
