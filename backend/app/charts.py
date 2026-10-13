"""Dibujo del audiograma con la simbología convencional (O rojo = derecho, X azul = izquierdo)."""

import io
import math

from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.figure import Figure

from .schemas import AudiometryResult, Ear

TICK_FREQUENCIES_HZ = (125, 250, 500, 1000, 2000, 4000, 8000)
MINOR_FREQUENCIES_HZ = (750, 1500, 3000, 6000)
Y_MIN, Y_MAX = -10, 120

BANDS = (
    (-10, 20, "#e8f5e9", "Normal"),
    (20, 35, "#f1f8e9", "Leve"),
    (35, 50, "#fffde7", "Moderada"),
    (50, 65, "#fff3e0", "Mod. severa"),
    (65, 80, "#fbe9e7", "Severa"),
    (80, 95, "#ffebee", "Profunda"),
    (95, 120, "#fce4ec", "Completa"),
)

EAR_STYLE = {
    Ear.right: {"color": "#d32f2f", "marker": "o", "label": "Oído derecho (O)", "dx": -0.035},
    Ear.left: {"color": "#1565c0", "marker": "x", "label": "Oído izquierdo (X)", "dx": 0.035},
}


def _x(frequency_hz: float) -> float:
    return math.log2(frequency_hz)


def _tick_label(frequency_hz: int) -> str:
    return f"{frequency_hz // 1000}k" if frequency_hz >= 1000 else str(frequency_hz)


def render_audiogram(result: AudiometryResult, dpi: int = 200) -> bytes:
    # API orientada a objetos (sin pyplot) para que sea segura entre hilos del servidor.
    fig = Figure(figsize=(7.2, 5.6), dpi=dpi)
    FigureCanvasAgg(fig)
    ax = fig.add_subplot(111)

    x_lo, x_hi = _x(125) - 0.4, _x(8000) + 0.4
    for lo, hi, color, label in BANDS:
        ax.axhspan(lo, hi, color=color, zorder=0)
        ax.text(x_hi - 0.05, (lo + hi) / 2, label, ha="right", va="center",
                fontsize=7, color="#757575", zorder=1)

    for ear, style in EAR_STYLE.items():
        points = result.by_ear(ear)
        if not points:
            continue
        # Pequeño desplazamiento horizontal para que O y X no se tapen si coinciden.
        xs = [_x(t.frequency_hz) + style["dx"] for t in points]
        ys = [t.threshold_db_hl for t in points]
        heard = [(x, y) for x, y, t in zip(xs, ys, points) if not t.no_response]
        if heard:
            ax.plot(*zip(*heard), color=style["color"], linewidth=1.4, zorder=3)
        if style["marker"] == "o":
            colors = {"facecolors": "white", "edgecolors": style["color"]}
        else:
            colors = {"color": style["color"]}
        ax.scatter(xs, ys, s=95, marker=style["marker"], linewidths=1.9, zorder=4,
                   label=style["label"], **colors)
        for x, y, t in zip(xs, ys, points):
            if t.no_response:
                # Flecha hacia abajo: sin respuesta al nivel máximo evaluado.
                ax.annotate("", xy=(x, y + 9), xytext=(x, y + 2),
                            arrowprops={"arrowstyle": "->", "color": style["color"], "lw": 1.6},
                            zorder=4)

    ax.set_xlim(x_lo, x_hi)
    ax.set_ylim(Y_MAX, Y_MIN)
    ax.set_xticks([_x(f) for f in TICK_FREQUENCIES_HZ])
    ax.set_xticklabels([_tick_label(f) for f in TICK_FREQUENCIES_HZ])
    ax.set_xticks([_x(f) for f in MINOR_FREQUENCIES_HZ], minor=True)
    ax.set_yticks(range(Y_MIN, Y_MAX + 1, 10))
    ax.xaxis.tick_top()
    ax.xaxis.set_label_position("top")
    ax.set_xlabel("Frecuencia (Hz)", fontsize=10, labelpad=8)
    ax.set_ylabel("Nivel de audición (dB HL)", fontsize=10)
    ax.grid(True, which="major", color="#9e9e9e", linewidth=0.6, alpha=0.7)
    ax.grid(True, which="minor", axis="x", color="#bdbdbd", linewidth=0.4, linestyle=":")
    ax.tick_params(labelsize=9)
    ax.legend(loc="lower left", fontsize=8, framealpha=0.95)
    fig.tight_layout()

    buf = io.BytesIO()
    fig.savefig(buf, format="png")
    return buf.getvalue()
