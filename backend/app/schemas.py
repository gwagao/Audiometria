from datetime import datetime
from enum import Enum
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

# Frecuencias audiométricas estándar (Hz)
FREQUENCIES_HZ = (125, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 8000)


class Ear(str, Enum):
    right = "right"
    left = "left"


class Patient(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    age: Optional[int] = Field(default=None, ge=0, le=120)
    sex: Optional[Literal["M", "F", "O"]] = None
    document: Optional[str] = Field(default=None, max_length=40)


class OutputDevice(BaseModel):
    name: str = Field(default="Desconocido", max_length=120)
    type: str = Field(default="unknown", max_length=40)
    calibration_offset_db: float = Field(default=0, ge=-40, le=40)


class Threshold(BaseModel):
    ear: Ear
    frequency_hz: int
    threshold_db_hl: float = Field(ge=-10, le=120)
    # True cuando no hubo respuesta al nivel máximo; threshold_db_hl es ese máximo.
    no_response: bool = False

    @field_validator("frequency_hz")
    @classmethod
    def _standard_frequency(cls, v: int) -> int:
        if v not in FREQUENCIES_HZ:
            raise ValueError(f"frecuencia no estándar: {v} Hz")
        return v


class AudiometryResult(BaseModel):
    patient: Patient
    performed_at: datetime
    device: OutputDevice = Field(default_factory=OutputDevice)
    method: str = Field(default="Hughson-Westlake modificado", max_length=80)
    thresholds: list[Threshold] = Field(min_length=1, max_length=2 * len(FREQUENCIES_HZ))
    false_positives: int = Field(default=0, ge=0)
    notes: Optional[str] = Field(default=None, max_length=2000)

    @field_validator("thresholds")
    @classmethod
    def _unique_points(cls, v: list[Threshold]) -> list[Threshold]:
        seen = set()
        for t in v:
            key = (t.ear, t.frequency_hz)
            if key in seen:
                raise ValueError(f"umbral duplicado: {t.ear.value} {t.frequency_hz} Hz")
            seen.add(key)
        return v

    def by_ear(self, ear: Ear) -> list[Threshold]:
        return sorted((t for t in self.thresholds if t.ear == ear), key=lambda t: t.frequency_hz)


class EarSummary(BaseModel):
    ear: Ear
    pta_db_hl: Optional[float]
    # True si algún umbral del promedio fue "sin respuesta": el PTA real es mayor o igual.
    pta_is_lower_bound: bool
    frequencies_used: list[int]
    category: Optional[str]
    category_label: str


class Analysis(BaseModel):
    right: EarSummary
    left: EarSummary
    observations: list[str]


class SessionInfo(BaseModel):
    id: str
    created_at: datetime
    patient_name: str
    performed_at: datetime


class SessionCreated(BaseModel):
    id: str
    analysis: Analysis
