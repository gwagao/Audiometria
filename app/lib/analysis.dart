import 'models.dart';

/// Espejo de backend/app/analysis.py para mostrar el resumen sin conexión.
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
