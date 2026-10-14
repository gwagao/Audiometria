import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models.dart';

const rightEarColor = Color(0xFFD32F2F);
const leftEarColor = Color(0xFF1565C0);

/// Dibuja el audiograma como imagen PNG (para el informe PDF).
Future<Uint8List> renderAudiogramPng(
  List<ThresholdPoint> thresholds, {
  Size size = const Size(460, 400),
  double pixelRatio = 3,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(pixelRatio)
    ..drawRect(Offset.zero & size, Paint()..color = Colors.white);
  _AudiogramPainter(thresholds, const TextStyle(fontSize: 11, color: Colors.black87))
      .paint(canvas, size);
  final image = await recorder.endRecording().toImage(
        (size.width * pixelRatio).round(),
        (size.height * pixelRatio).round(),
      );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Audiograma con la simbología convencional: O rojo = derecho, X azul = izquierdo.
class AudiogramChart extends StatelessWidget {
  const AudiogramChart({super.key, required this.thresholds});

  final List<ThresholdPoint> thresholds;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1.15,
          child: CustomPaint(
            painter: _AudiogramPainter(
              thresholds,
              Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.black87),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(color: rightEarColor, symbol: 'O', label: 'Derecho'),
            SizedBox(width: 24),
            _Legend(color: leftEarColor, symbol: 'X', label: 'Izquierdo'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.symbol, required this.label});

  final Color color;
  final String symbol;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(symbol, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _AudiogramPainter extends CustomPainter {
  _AudiogramPainter(this.thresholds, this.textStyle);

  final List<ThresholdPoint> thresholds;
  final TextStyle textStyle;

  static const _tickFrequencies = [125, 250, 500, 1000, 2000, 4000, 8000];
  static const _minDb = -10.0;
  static const _maxDb = 120.0;
  static const _bands = [
    (-10.0, 20.0, Color(0xFFE8F5E9), 'Normal'),
    (20.0, 35.0, Color(0xFFF1F8E9), 'Leve'),
    (35.0, 50.0, Color(0xFFFFFDE7), 'Moderada'),
    (50.0, 65.0, Color(0xFFFFF3E0), 'Mod. severa'),
    (65.0, 80.0, Color(0xFFFBE9E7), 'Severa'),
    (80.0, 95.0, Color(0xFFFFEBEE), 'Profunda'),
    (95.0, 120.0, Color(0xFFFCE4EC), 'Completa'),
  ];

  static double _log2(num v) => math.log(v) / math.ln2;

  void _text(Canvas canvas, String text, Offset anchor,
      {TextStyle? style, Alignment align = Alignment.center}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style ?? textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    // `align` indica qué punto del texto coincide con `anchor`.
    final dx = anchor.dx - tp.width * (align.x + 1) / 2;
    final dy = anchor.dy - tp.height * (align.y + 1) / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(40, 34, size.width - 8, size.height - 6);
    final xLo = _log2(125) - 0.4;
    final xHi = _log2(8000) + 0.4;
    double px(num frequencyHz) =>
        plot.left + (_log2(frequencyHz) - xLo) / (xHi - xLo) * plot.width;
    double py(num db) => plot.top + (db - _minDb) / (_maxDb - _minDb) * plot.height;

    final bandLabel = textStyle.copyWith(fontSize: 9, color: Colors.black45);
    for (final (lo, hi, color, label) in _bands) {
      canvas.drawRect(
          Rect.fromLTRB(plot.left, py(lo), plot.right, py(hi)), Paint()..color = color);
      _text(canvas, label, Offset(plot.right - 4, py((lo + hi) / 2)),
          style: bandLabel, align: Alignment.centerRight);
    }

    final grid = Paint()
      ..color = Colors.black26
      ..strokeWidth = 0.6;
    for (var db = _minDb; db <= _maxDb; db += 10) {
      canvas.drawLine(Offset(plot.left, py(db)), Offset(plot.right, py(db)), grid);
      _text(canvas, db.toInt().toString(), Offset(plot.left - 6, py(db)),
          align: Alignment.centerRight);
    }
    for (final f in _tickFrequencies) {
      canvas.drawLine(Offset(px(f), plot.top), Offset(px(f), plot.bottom), grid);
      _text(canvas, f >= 1000 ? '${f ~/ 1000}k' : '$f', Offset(px(f), plot.top - 4),
          align: Alignment.bottomCenter);
    }
    _text(canvas, 'Frecuencia (Hz)', Offset(plot.center.dx, 0), align: Alignment.topCenter);
    canvas.drawRect(
        plot,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black54);

    canvas.save();
    canvas.translate(2, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _text(canvas, 'Nivel de audición (dB HL)', Offset.zero, align: Alignment.topCenter);
    canvas.restore();

    _drawEar(canvas, Ear.right, rightEarColor, -3, px, py);
    _drawEar(canvas, Ear.left, leftEarColor, 3, px, py);
  }

  void _drawEar(Canvas canvas, Ear ear, Color color, double dx,
      double Function(num) px, double Function(num) py) {
    final points = thresholds.where((t) => t.ear == ear).toList()
      ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    // La línea solo une los puntos con respuesta.
    final line = Path();
    var started = false;
    for (final t in points.where((t) => !t.noResponse)) {
      final p = Offset(px(t.frequencyHz) + dx, py(t.thresholdDbHl));
      started ? line.lineTo(p.dx, p.dy) : line.moveTo(p.dx, p.dy);
      started = true;
    }
    canvas.drawPath(line, Paint.from(stroke)..strokeWidth = 1.4);

    const r = 6.5;
    for (final t in points) {
      final c = Offset(px(t.frequencyHz) + dx, py(t.thresholdDbHl));
      if (ear == Ear.right) {
        canvas.drawCircle(c, r, Paint()..color = Colors.white);
        canvas.drawCircle(c, r, stroke);
      } else {
        canvas.drawLine(c + const Offset(-r, -r), c + const Offset(r, r), stroke);
        canvas.drawLine(c + const Offset(-r, r), c + const Offset(r, -r), stroke);
      }
      if (t.noResponse) {
        // Flecha hacia abajo: sin respuesta al nivel máximo evaluado.
        final tip = c + const Offset(0, r + 14);
        canvas.drawLine(c + const Offset(0, r + 2), tip, stroke);
        canvas.drawLine(tip, tip + const Offset(-4, -5), stroke);
        canvas.drawLine(tip, tip + const Offset(4, -5), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_AudiogramPainter old) =>
      old.thresholds != thresholds || old.textStyle != textStyle;
}
