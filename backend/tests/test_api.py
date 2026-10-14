import pytest
from fastapi.testclient import TestClient

from app.analysis import classify
from app.main import app


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("AUDIOMETRIA_DB", str(tmp_path / "test.db"))
    return TestClient(app)


def make_payload(right=None, left=None, **extra):
    right = right or {250: 10, 500: 10, 1000: 15, 2000: 15, 4000: 20, 8000: 25}
    left = left or {250: 15, 500: 20, 1000: 25, 2000: 30, 4000: 45, 8000: 60}
    thresholds = [
        {"ear": ear, "frequency_hz": f, "threshold_db_hl": db}
        for ear, points in (("right", right), ("left", left))
        for f, db in points.items()
    ]
    return {
        "patient": {"name": "María Pérez Ñandú", "age": 42, "sex": "F"},
        "performed_at": "2026-10-09T10:30:00",
        "device": {"name": "Sony WH-1000XM4", "type": "wired"},
        "thresholds": thresholds,
        **extra,
    }


@pytest.mark.parametrize(
    "pta, expected",
    [(-5, "normal"), (19.9, "normal"), (20, "mild"), (34.9, "mild"), (35, "moderate"),
     (50, "moderately_severe"), (65, "severe"), (80, "profound"), (95, "complete"), (120, "complete")],
)
def test_classify_boundaries(pta, expected):
    assert classify(pta)[0] == expected


def test_health(client):
    assert client.get("/health").json()["status"] == "ok"


def test_analyze_pta_and_category(client):
    data = client.post("/api/v1/analyze", json=make_payload()).json()
    assert data["right"]["pta_db_hl"] == 15.0  # (10+15+15+20)/4
    assert data["right"]["category"] == "normal"
    assert data["left"]["pta_db_hl"] == 30.0  # (20+25+30+45)/4
    assert data["left"]["category"] == "mild"
    assert any("Asimetría" in o for o in data["observations"])


def test_analyze_insufficient_data(client):
    data = client.post("/api/v1/analyze", json=make_payload(right={1000: 10, 8000: 10})).json()
    assert data["right"]["pta_db_hl"] is None
    assert data["right"]["category"] is None


def test_no_response_marks_lower_bound(client):
    payload = make_payload()
    for t in payload["thresholds"]:
        if t["ear"] == "left" and t["frequency_hz"] == 4000:
            t.update(threshold_db_hl=85, no_response=True)
    data = client.post("/api/v1/analyze", json=payload).json()
    assert data["left"]["pta_is_lower_bound"] is True
    assert data["right"]["pta_is_lower_bound"] is False


def test_audiogram_png(client):
    r = client.post("/api/v1/audiogram.png", json=make_payload())
    assert r.status_code == 200
    assert r.headers["content-type"] == "image/png"
    assert r.content.startswith(b"\x89PNG")


def test_pdf_endpoints_removed(client):
    # El informe PDF ahora se genera en el teléfono.
    assert client.post("/api/v1/report.pdf", json=make_payload()).status_code == 404


def test_session_roundtrip(client):
    r = client.post("/api/v1/sessions", json=make_payload(notes="Paciente con <tinnitus> & vértigo"))
    assert r.status_code == 201
    session_id = r.json()["id"]
    assert r.json()["analysis"]["left"]["category"] == "mild"

    sessions = client.get("/api/v1/sessions").json()
    assert [s["id"] for s in sessions] == [session_id]
    assert sessions[0]["patient_name"] == "María Pérez Ñandú"

    stored = client.get(f"/api/v1/sessions/{session_id}").json()
    assert len(stored["thresholds"]) == 12

    png = client.get(f"/api/v1/sessions/{session_id}/audiogram.png")
    assert png.content.startswith(b"\x89PNG")

    assert client.delete(f"/api/v1/sessions/{session_id}").status_code == 204
    assert client.get(f"/api/v1/sessions/{session_id}").status_code == 404


def test_rejects_invalid_input(client):
    bad_freq = make_payload(right={1234: 10})
    assert client.post("/api/v1/analyze", json=bad_freq).status_code == 422

    duplicated = make_payload()
    duplicated["thresholds"].append(duplicated["thresholds"][0])
    assert client.post("/api/v1/analyze", json=duplicated).status_code == 422

    out_of_range = make_payload(right={1000: 200})
    assert client.post("/api/v1/analyze", json=out_of_range).status_code == 422
