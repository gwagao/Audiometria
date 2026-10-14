import 'dart:math' as math;

import 'models.dart';

/// Mismos criterios que backend/app/analysis.py.
const ptaFrequenciesHz = [500, 1000, 2000, 4000];
const minPtaFrequencies = 3;

class HearingCategory {
  const HearingCategory(this.upperDbHl, this.label, this.color);

  /// Límite superior exclusivo en dB HL.
  final double upperDbHl;
  final String label;
  final int color;
}

/// Grados de la OMS (World Report on Hearing, 2021).
const categories = [
  HearingCategory(20, 'Audición normal', 0xFF2E7D32),
  HearingCategory(35, 'Pérdida leve', 0xFF7CB342),
  HearingCategory(50, 'Pérdida moderada', 0xFFF9A825),
  HearingCategory(65, 'Pérdida moderadamente severa', 0xFFEF6C00),
  HearingCategory(80, 'Pérdida severa', 0xFFD84315),
  HearingCategory(95, 'Pérdida profunda', 0xFFC62828),
  HearingCategory(double.infinity, 'Pérdida completa / sordera', 0xFF6A1B9A),
];

HearingCategory classify(double ptaDbHl) =>
    categories.firstWhere((c) => ptaDbHl < c.upperDbHl);

class EarSummary {
  const EarSummary({required this.ear, this.ptaDbHl, this.isLowerBound = false, this.category});

  final Ear ear;
  final double? ptaDbHl;

  /// Algún umbral del promedio fue "sin respuesta": el PTA real es mayor o igual.
  final bool isLowerBound;
  final HearingCategory? category;

  String get ptaText => ptaDbHl == null
      ? '—'
      : '${isLowerBound ? '≥ ' : ''}${ptaDbHl!.toStringAsFixed(1)} dB HL';

  String get categoryLabel => category?.label ?? 'Datos insuficientes';
}

EarSummary summarizeEar(AudiometryResult result, Ear ear) {
  final points =
      result.byEar(ear).where((t) => ptaFrequenciesHz.contains(t.frequencyHz)).toList();
  if (points.length < minPtaFrequencies) return EarSummary(ear: ear);
  final pta = points.fold<int>(0, (sum, t) => sum + t.thresholdDbHl) / points.length;
  return EarSummary(
    ear: ear,
    ptaDbHl: pta,
    isLowerBound: points.any((t) => t.noResponse),
    category: classify(pta),
  );
}

const asymmetryDb = 15;

/// Hallazgos que merecen mención en el informe.
List<String> observations(AudiometryResult result) {
  final right = summarizeEar(result, Ear.right);
  final left = summarizeEar(result, Ear.left);
  final notes = <String>[];

  if (right.ptaDbHl != null && left.ptaDbHl != null) {
    final diff = (right.ptaDbHl! - left.ptaDbHl!).abs();
    if (diff >= asymmetryDb) {
      final worse = right.ptaDbHl! > left.ptaDbHl! ? 'derecho' : 'izquierdo';
      notes.add('Asimetría entre oídos de ${diff.toStringAsFixed(0)} dB en el promedio '
          'tonal (peor oído: $worse). Se recomienda evaluación profesional.');
    }
  }

  for (final summary in [right, left]) {
    final name = summary.ear.label.toLowerCase();
    if (summary.isLowerBound) {
      notes.add('En el $name hubo frecuencias sin respuesta al nivel máximo; '
          'el promedio real es igual o mayor al indicado.');
    }
    final high = result.byEar(summary.ear).where((t) => t.frequencyHz >= 4000);
    if (summary.category == categories.first &&
        high.isNotEmpty &&
        high.map((t) => t.thresholdDbHl).reduce(math.max) >= 35) {
      notes.add('Caída en frecuencias agudas en el $name pese a un promedio normal.');
    }
  }

  if (result.falsePositives >= 3) {
    notes.add('Se registraron ${result.falsePositives} respuestas sin tono presente; '
        'la fiabilidad de la prueba puede ser reducida.');
  }
  return notes;
}

String summaryText(AudiometryResult result) {
  final lines = <String>[
    'Audiometría tonal — ${result.patient.name}',
    'Fecha: ${formatDateTime(result.performedAt)}',
    'Dispositivo: ${result.device.name} (${result.device.typeLabel})',
    '',
  ];
  for (final ear in Ear.values) {
    final s = summarizeEar(result, ear);
    lines.add('${ear.label}: PTA ${s.ptaText} — ${s.categoryLabel}');
    lines.add(result
        .byEar(ear)
        .map((t) => '  ${t.frequencyHz} Hz: ${t.noResponse ? '>' : ''}${t.thresholdDbHl} dB')
        .join('\n'));
  }
  lines
    ..add('')
    ..add('Prueba de cribado orientativa; no sustituye una evaluación profesional.');
  return lines.join('\n');
}
