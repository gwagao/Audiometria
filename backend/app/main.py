"""API opcional: historial de pruebas y análisis. El informe PDF lo genera la app."""

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import Response

from . import storage
from .analysis import analyze
from .charts import render_audiogram
from .schemas import Analysis, AudiometryResult, SessionCreated, SessionInfo

app = FastAPI(title="Audiometría API", version="1.1.0")


def _load(session_id: str) -> AudiometryResult:
    result = storage.get(session_id)
    if result is None:
        raise HTTPException(status_code=404, detail="Sesión no encontrada")
    return result


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "audiometria", "version": app.version}


@app.post("/api/v1/analyze", response_model=Analysis)
def analyze_result(result: AudiometryResult) -> Analysis:
    return analyze(result)


@app.post("/api/v1/audiogram.png")
def audiogram_png(result: AudiometryResult) -> Response:
    return Response(render_audiogram(result), media_type="image/png")


@app.post("/api/v1/sessions", response_model=SessionCreated, status_code=201)
def create_session(result: AudiometryResult) -> SessionCreated:
    return SessionCreated(id=storage.save(result), analysis=analyze(result))


@app.get("/api/v1/sessions", response_model=list[SessionInfo])
def list_sessions(limit: int = Query(default=100, ge=1, le=500)) -> list[SessionInfo]:
    return storage.list_sessions(limit)


@app.get("/api/v1/sessions/{session_id}", response_model=AudiometryResult)
def get_session(session_id: str) -> AudiometryResult:
    return _load(session_id)


@app.get("/api/v1/sessions/{session_id}/audiogram.png")
def session_audiogram(session_id: str) -> Response:
    return Response(render_audiogram(_load(session_id)), media_type="image/png")


@app.delete("/api/v1/sessions/{session_id}", status_code=204)
def delete_session(session_id: str) -> Response:
    if not storage.delete(session_id):
        raise HTTPException(status_code=404, detail="Sesión no encontrada")
    return Response(status_code=204)
