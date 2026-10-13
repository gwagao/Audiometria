"""Promedio tonal puro (PTA) y clasificación del grado de pérdida auditiva."""

from .schemas import Analysis, AudiometryResult, Ear, EarSummary

PTA_FREQUENCIES_HZ = (500, 1000, 2000, 4000)
MIN_PTA_FREQUENCIES = 3
ASYMMETRY_DB = 15

# Grados de la OMS (World Report on Hearing, 2021): límite superior exclusivo en dB HL.
CATEGORIES = (
    (20, "normal", "Audición normal"),
    (35, "mild", "Pérdida leve"),
    (50, "moderate", "Pérdida moderada"),
    (65, "moderately_severe", "Pérdida moderadamente severa"),
    (80, "severe", "Pérdida severa"),
    (95, "profound", "Pérdida profunda"),
    (float("inf"), "complete", "Pérdida completa / sordera"),
)

EAR_LABELS = {Ear.right: "Oído derecho", Ear.left: "Oído izquierdo"}


def classify(pta_db_hl: float) -> tuple[str, str]:
    for upper, key, label in CATEGORIES:
        if pta_db_hl < upper:
            return key, label
    raise AssertionError("unreachable")


def summarize_ear(result: AudiometryResult, ear: Ear) -> EarSummary:
    points = [t for t in result.by_ear(ear) if t.frequency_hz in PTA_FREQUENCIES_HZ]
    if len(points) < MIN_PTA_FREQUENCIES:
        return EarSummary(
            ear=ear,
            pta_db_hl=None,
            pta_is_lower_bound=False,
            frequencies_used=[t.frequency_hz for t in points],
            category=None,
            category_label="Datos insuficientes",
        )
    pta = round(sum(t.threshold_db_hl for t in points) / len(points), 1)
    key, label = classify(pta)
    return EarSummary(
        ear=ear,
        pta_db_hl=pta,
        pta_is_lower_bound=any(t.no_response for t in points),
        frequencies_used=[t.frequency_hz for t in points],
        category=key,
        category_label=label,
    )


def analyze(result: AudiometryResult) -> Analysis:
    right = summarize_ear(result, Ear.right)
    left = summarize_ear(result, Ear.left)
    observations: list[str] = []

    if right.pta_db_hl is not None and left.pta_db_hl is not None:
        diff = abs(right.pta_db_hl - left.pta_db_hl)
        if diff >= ASYMMETRY_DB:
            worse = "derecho" if right.pta_db_hl > left.pta_db_hl else "izquierdo"
            observations.append(
                f"Asimetría entre oídos de {diff:.0f} dB en el promedio tonal "
                f"(peor oído: {worse}). Se recomienda evaluación profesional."
            )

    for summary in (right, left):
        name = EAR_LABELS[summary.ear].lower()
        if summary.pta_is_lower_bound:
            observations.append(
                f"En el {name} hubo frecuencias sin respuesta al nivel máximo; "
                "el promedio real es igual o mayor al indicado."
            )
        high = [t for t in result.by_ear(summary.ear) if t.frequency_hz >= 4000]
        if (
            summary.category == "normal"
            and high
            and max(t.threshold_db_hl for t in high) >= 35
        ):
            observations.append(
                f"Caída en frecuencias agudas en el {name} pese a un promedio normal."
            )

    if result.false_positives >= 3:
        observations.append(
            f"Se registraron {result.false_positives} respuestas sin tono presente; "
            "la fiabilidad de la prueba puede ser reducida."
        )
    return Analysis(right=right, left=left, observations=observations)
