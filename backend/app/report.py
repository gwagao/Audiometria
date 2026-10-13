"""Generación del informe PDF de la audiometría."""

import io
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Image, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from .analysis import EAR_LABELS, analyze
from .charts import render_audiogram
from .schemas import AudiometryResult, Ear, EarSummary

SEX_LABELS = {"M": "Masculino", "F": "Femenino", "O": "Otro"}
DEVICE_TYPE_LABELS = {
    "wired": "Audífonos con cable",
    "usb": "Audífonos USB",
    "bluetooth": "Audífonos Bluetooth",
    "hearing_aid": "Audífono médico",
    "speaker": "Altavoz del teléfono",
}
DISCLAIMER = (
    "Este informe proviene de una prueba de cribado realizada con un teléfono y audífonos "
    "de consumo sin calibración certificada. Los valores son orientativos y no constituyen "
    "un diagnóstico médico. Ante cualquier resultado alterado o duda, consulte a un "
    "especialista en audiología u otorrinolaringología."
)

ACCENT = colors.HexColor("#1565c0")
GRID = colors.HexColor("#bdbdbd")
HEADER_BG = colors.HexColor("#e3f2fd")


def _styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle("title", parent=base["Title"], fontSize=18, textColor=ACCENT,
                                spaceAfter=2),
        "subtitle": ParagraphStyle("subtitle", parent=base["Normal"], fontSize=9,
                                   textColor=colors.grey, alignment=1, spaceAfter=8),
        "h2": ParagraphStyle("h2", parent=base["Heading2"], fontSize=12, textColor=ACCENT,
                             spaceBefore=8, spaceAfter=4),
        "body": ParagraphStyle("body", parent=base["Normal"], fontSize=9.5, leading=13),
        "small": ParagraphStyle("small", parent=base["Normal"], fontSize=8, leading=10.5,
                                textColor=colors.HexColor("#616161")),
    }


def _format_level(value: float, no_response: bool = False) -> str:
    text = f"{value:g}"
    return f"&gt;{text} (SR)" if no_response else text


def _info_table(result: AudiometryResult, styles) -> Table:
    p = result.patient
    d = result.device
    rows = [
        ("Paciente", p.name, "Fecha", result.performed_at.strftime("%d/%m/%Y %H:%M")),
        ("Edad", f"{p.age} años" if p.age is not None else "-",
         "Sexo", SEX_LABELS.get(p.sex or "", "-")),
        ("Documento", p.document or "-", "Método", result.method),
        ("Dispositivo", f"{d.name} ({DEVICE_TYPE_LABELS.get(d.type, d.type)})",
         "Ajuste de calibración", f"{d.calibration_offset_db:+g} dB"),
    ]
    data = [
        [Paragraph(f"<b>{escape(k1)}</b>", styles["body"]), Paragraph(escape(str(v1)), styles["body"]),
         Paragraph(f"<b>{escape(k2)}</b>", styles["body"]), Paragraph(escape(str(v2)), styles["body"])]
        for k1, v1, k2, v2 in rows
    ]
    table = Table(data, colWidths=[24 * mm, 66 * mm, 36 * mm, 54 * mm])
    table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LINEBELOW", (0, 0), (-1, -1), 0.3, GRID),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]))
    return table


def _threshold_table(result: AudiometryResult, styles) -> Table:
    frequencies = sorted({t.frequency_hz for t in result.thresholds})
    by_key = {(t.ear, t.frequency_hz): t for t in result.thresholds}
    header = ["Frecuencia (Hz)"] + [str(f) for f in frequencies]
    data = [header]
    for ear in (Ear.right, Ear.left):
        row = [EAR_LABELS[ear]]
        for f in frequencies:
            t = by_key.get((ear, f))
            row.append(Paragraph(_format_level(t.threshold_db_hl, t.no_response), styles["body"])
                       if t else "-")
        data.append(row)
    width = (180 - 34) / max(len(frequencies), 1)
    table = Table(data, colWidths=[34 * mm] + [width * mm] * len(frequencies))
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), HEADER_BG),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTNAME", (0, 1), (0, -1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("TEXTCOLOR", (0, 1), (0, 1), colors.HexColor("#d32f2f")),
        ("TEXTCOLOR", (0, 2), (0, 2), ACCENT),
        ("GRID", (0, 0), (-1, -1), 0.4, GRID),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    return table


def _summary_row(summary: EarSummary) -> list[str]:
    if summary.pta_db_hl is None:
        pta = "-"
    else:
        pta = f"{'>= ' if summary.pta_is_lower_bound else ''}{summary.pta_db_hl:g} dB HL"
    used = ", ".join(str(f) for f in summary.frequencies_used) or "-"
    return [EAR_LABELS[summary.ear], pta, summary.category_label, used]


def build_pdf(result: AudiometryResult) -> bytes:
    styles = _styles()
    analysis = analyze(result)
    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm,
        topMargin=14 * mm, bottomMargin=14 * mm,
        title=f"Audiometría - {result.patient.name}", author="Audiometría App",
    )

    story = [
        Paragraph("Informe de audiometría tonal", styles["title"]),
        Paragraph("Prueba de cribado por vía aérea con tonos puros", styles["subtitle"]),
        _info_table(result, styles),
        Paragraph("Audiograma", styles["h2"]),
    ]

    chart = Image(io.BytesIO(render_audiogram(result)))
    chart_width = 124 * mm
    chart.drawHeight = chart_width * chart.imageHeight / chart.imageWidth
    chart.drawWidth = chart_width
    story.append(chart)

    story.append(Paragraph("Umbrales (dB HL)", styles["h2"]))
    story.append(_threshold_table(result, styles))
    if any(t.no_response for t in result.thresholds):
        story.append(Spacer(1, 2))
        story.append(Paragraph("SR: sin respuesta al nivel máximo evaluado.", styles["small"]))

    story.append(Paragraph("Resumen", styles["h2"]))
    summary = Table(
        [["Oído", "Promedio tonal (PTA)", "Clasificación (OMS)", "Frecuencias del PTA (Hz)"],
         _summary_row(analysis.right), _summary_row(analysis.left)],
        colWidths=[34 * mm, 40 * mm, 58 * mm, 48 * mm],
    )
    summary.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), HEADER_BG),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("GRID", (0, 0), (-1, -1), 0.4, GRID),
    ]))
    story.append(summary)

    if analysis.observations or result.notes:
        story.append(Paragraph("Observaciones", styles["h2"]))
        for text in analysis.observations:
            story.append(Paragraph(f"• {escape(text)}", styles["body"]))
        if result.notes:
            story.append(Paragraph(f"<b>Notas:</b> {escape(result.notes)}", styles["body"]))

    story.append(Spacer(1, 8))
    story.append(Paragraph(DISCLAIMER, styles["small"]))

    doc.build(story)
    return buf.getvalue()
