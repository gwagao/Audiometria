import 'dart:convert';

import 'package:audiometria/analysis.dart';
import 'package:audiometria/calibration.dart';
import 'package:audiometria/models.dart';
import 'package:audiometria/pdf_report.dart';
import 'package:audiometria/threshold_search.dart';
import 'package:audiometria/widgets/audiogram_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula un paciente ideal que oye todo tono en su umbral real o por encima.
ThresholdSearch runSearch(int trueThreshold, {int maxLevel = 80}) {
  final search = ThresholdSearch(maxLevel: maxLevel);
  while (!search.done) {
    search.record(search.level >= trueThreshold);
  }
  return search;
}

AudiometryResult sampleResult() => AudiometryResult(
      patient: const Patient(name: 'María Pérez', age: 42, sex: 'F'),
      performedAt: DateTime(2026, 10, 9, 10, 30),
      device: const OutputDevice(name: 'Sony', type: 'wired'),
      thresholds: [
        for (final (f, db) in [(500, 10), (1000, 15), (2000, 15), (4000, 20)])
          ThresholdPoint(ear: Ear.right, frequencyHz: f, thresholdDbHl: db),
        for (final (f, db) in [(500, 20), (1000, 25), (2000, 30), (4000, 45)])
          ThresholdPoint(ear: Ear.left, frequencyHz: f, thresholdDbHl: db),
        const ThresholdPoint(
            ear: Ear.left, frequencyHz: 8000, thresholdDbHl: 80, noResponse: true),
      ],
    );

void main() {
  group('ThresholdSearch', () {
    test('encuentra el umbral de un paciente ideal', () {
      for (final t in [-10, -5, 0, 15, 30, 35, 55, 80]) {
        final search = runSearch(t);
        expect(search.threshold, t, reason: 'umbral real $t');
        expect(search.noResponse, isFalse);
      }
    });

    test('el nivel sube mientras no hay respuesta', () {
      final search = ThresholdSearch(maxLevel: 80);
      final levels = <int>[];
      for (var i = 0; i < 4; i++) {
        levels.add(search.level);
        search.record(false);
      }
      expect(levels, [30, 40, 50, 60]);
    });

    test('baja 10 dB tras responder y sube 5 dB tras no responder', () {
      final search = ThresholdSearch(maxLevel: 80);
      search.record(true);
      expect(search.level, 20);
      search.record(false);
      expect(search.level, 25);
    });

    test('marca sin respuesta al superar el máximo', () {
      final search = runSearch(200, maxLevel: 70);
      expect(search.noResponse, isTrue);
      expect(search.threshold, 70);
    });

    test('termina aunque las respuestas sean inconsistentes', () {
      final search = ThresholdSearch(maxLevel: 80);
      var heard = false;
      while (!search.done) {
        // Solo responde al bajar: nunca acumula dos respuestas ascendentes.
        search.record(heard = !heard && search.level > 60);
      }
      expect(search.trials, lessThanOrEqualTo(search.maxTrials));
    });
  });

  group('calibración', () {
    test('la amplitud sube 20 dB por cada factor de 10', () {
      final a = amplitudeFor(1000, 20);
      final b = amplitudeFor(1000, 40);
      expect(b / a, closeTo(10, 1e-9));
    });

    test('nunca supera la escala completa', () {
      expect(amplitudeFor(125, 120), 1.0);
      expect(amplitudeFor(1000, maxLevelFor(1000)), lessThanOrEqualTo(1.0));
    });

    test('el ajuste desplaza el nivel máximo', () {
      expect(maxLevelFor(1000), 90); // 100 - 7 = 93 -> 90
      expect(maxLevelFor(1000, offsetDb: 10), 80);
    });
  });

  group('análisis', () {
    test('PTA y clasificación coinciden con el backend', () {
      final result = sampleResult();
      final right = summarizeEar(result, Ear.right);
      final left = summarizeEar(result, Ear.left);
      expect(right.ptaDbHl, 15);
      expect(right.categoryLabel, 'Audición normal');
      expect(left.ptaDbHl, 30);
      expect(left.categoryLabel, 'Pérdida leve');
      expect(left.isLowerBound, isFalse); // 8000 Hz no entra en el PTA
    });

    test('límites de las categorías', () {
      expect(classify(19.9).label, 'Audición normal');
      expect(classify(20).label, 'Pérdida leve');
      expect(classify(95).label, 'Pérdida completa / sordera');
    });

    test('datos insuficientes sin 3 frecuencias del PTA', () {
      final result = AudiometryResult(
        patient: const Patient(name: 'X'),
        performedAt: DateTime(2026),
        device: OutputDevice.speaker,
        thresholds: const [ThresholdPoint(ear: Ear.right, frequencyHz: 1000, thresholdDbHl: 10)],
      );
      expect(summarizeEar(result, Ear.right).ptaDbHl, isNull);
    });
  });

  test('el resultado sobrevive a JSON', () {
    final original = sampleResult().withNotes('nota');
    final copy = AudiometryResult.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(copy.toJson()), jsonEncode(original.toJson()));
    expect(copy.thresholds.last.noResponse, isTrue);
  });

  test('observaciones: asimetría y falsos positivos', () {
    final base = sampleResult();
    final result = AudiometryResult(
      patient: base.patient,
      performedAt: base.performedAt,
      device: base.device,
      thresholds: base.thresholds,
      falsePositives: 3,
    );
    final notes = observations(result);
    expect(notes.any((n) => n.startsWith('Asimetría')), isTrue);
    expect(notes.any((n) => n.contains('3 respuestas sin tono')), isTrue);
  });

  testWidgets('genera el informe PDF en el teléfono', (tester) async {
    final bytes = await tester.runAsync(
        () => buildReportPdf(sampleResult().withNotes('Refiere zumbido <ocasional> & más')));
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(20000)); // incluye la imagen del audiograma
  });

  testWidgets('el audiograma se dibuja sin errores', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AudiogramChart(thresholds: sampleResult().thresholds),
        ),
      ),
    ));
    expect(find.text('Derecho'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
