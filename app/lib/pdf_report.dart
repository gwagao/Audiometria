import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'analysis.dart';
import 'models.dart';
import 'widgets/audiogram_chart.dart';

/// Informe PDF generado en el propio teléfono, sin servidor.

const _disclaimer =
    'Este informe proviene de una prueba de cribado realizada con un teléfono y audífonos '
    'de consumo sin calibración certificada. Los valores son orientativos y no constituyen '
    'un diagnóstico médico. Ante cualquier resultado alterado o duda, consulte a un '
    'especialista en audiología u otorrinolaringología.';

const _sexLabels = {'M': 'Masculino', 'F': 'Femenino', 'O': 'Otro'};

final _accent = PdfColor.fromInt(0xFF1565C0);
final _grid = PdfColor.fromInt(0xFFBDBDBD);
final _headerBg = PdfColor.fromInt(0xFFE3F2FD);
final _muted = PdfColor.fromInt(0xFF616161);

PdfColor _earColor(Ear ear) =>
    PdfColor.fromInt((ear == Ear.right ? rightEarColor : leftEarColor).toARGB32());

Future<Uint8List> buildReportPdf(AudiometryResult result) async {
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
  );
  final chart = pw.MemoryImage(await renderAudiogramPng(result.thresholds));
  final notes = observations(result);

  final doc = pw.Document(
    title: 'Audiometría - ${result.patient.name}',
    author: 'Audiometría App',
  );
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      theme: theme.copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 9.5)),
    ),
    build: (context) => [
      pw.Center(
        child: pw.Text('Informe de audiometría tonal',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _accent)),
      ),
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text('Prueba de cribado por vía aérea con tonos puros',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
      ),
      pw.SizedBox(height: 10),
      _infoTable(result),
      _heading('Audiograma'),
      pw.Center(child: pw.Image(chart, width: 300)),
      pw.SizedBox(height: 4),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
        _legend('O', 'Oído derecho', Ear.right),
        pw.SizedBox(width: 24),
        _legend('X', 'Oído izquierdo', Ear.left),
      ]),
      _heading('Umbrales (dB HL)'),
      _thresholdTable(result),
      if (result.thresholds.any((t) => t.noResponse))
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text('SR: sin respuesta al nivel máximo evaluado.',
              style: pw.TextStyle(fontSize: 8, color: _muted)),
        ),
      _heading('Resumen'),
      _summaryTable(result),
      if (notes.isNotEmpty || (result.notes?.isNotEmpty ?? false)) ...[
        _heading('Observaciones'),
        for (final note in notes)
          pw.Bullet(
            text: note,
            style: const pw.TextStyle(fontSize: 9.5),
            margin: const pw.EdgeInsets.only(bottom: 2),
          ),
        if (result.notes?.isNotEmpty ?? false)
          pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Notas: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.TextSpan(text: result.notes),
            ]),
          ),
      ],
      pw.SizedBox(height: 10),
      pw.Text(_disclaimer, style: pw.TextStyle(fontSize: 8, color: _muted)),
    ],
  ));
  return doc.save();
}

/// Genera el PDF y lo guarda en la carpeta temporal para compartirlo.
Future<File> saveReportPdf(AudiometryResult result) async {
  final bytes = await buildReportPdf(result);
  final dir = await getTemporaryDirectory();
  final d = result.performedAt;
  String two(int n) => n.toString().padLeft(2, '0');
  final name =
      'audiometria_${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}.pdf';
  return File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
}

pw.Widget _heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _accent)),
    );

pw.Widget _legend(String symbol, String label, Ear ear) => pw.Row(children: [
      pw.Text(symbol,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _earColor(ear))),
      pw.SizedBox(width: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)),
    ]);

pw.Widget _infoTable(AudiometryResult result) {
  final p = result.patient;
  final d = result.device;
  final offset = d.calibrationOffsetDb;
  final rows = [
    ['Paciente', p.name, 'Fecha', formatDateTime(result.performedAt)],
    ['Edad', p.age != null ? '${p.age} años' : '-', 'Sexo', _sexLabels[p.sex] ?? '-'],
    ['Documento', p.document ?? '-', 'Método', result.method],
    [
      'Dispositivo',
      '${d.name} (${d.typeLabel})',
      'Ajuste de calibración',
      '${offset >= 0 ? '+' : ''}${offset.toStringAsFixed(0)} dB',
    ],
  ];
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  return pw.Table(
    columnWidths: const {
      0: pw.FixedColumnWidth(68),
      1: pw.FlexColumnWidth(3),
      2: pw.FixedColumnWidth(100),
      3: pw.FlexColumnWidth(2.4),
    },
    border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _grid, width: 0.3)),
    children: [
      for (final r in rows)
        pw.TableRow(children: [
          for (var i = 0; i < r.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              child: pw.Text(r[i], style: i.isEven ? bold : null),
            ),
        ]),
    ],
  );
}

pw.Widget _table(List<List<String>> rows, {Map<int, PdfColor> firstCellColors = const {}}) {
  return pw.TableHelper.fromTextArray(
    data: rows,
    border: pw.TableBorder.all(color: _grid, width: 0.4),
    headerDecoration: pw.BoxDecoration(color: _headerBg),
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellAlignment: pw.Alignment.centerLeft,
    cellPadding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
    textStyleBuilder: (column, _, row) => column == 0 && firstCellColors.containsKey(row)
        ? pw.TextStyle(
            fontSize: 9, fontWeight: pw.FontWeight.bold, color: firstCellColors[row])
        : null,
  );
}

pw.Widget _thresholdTable(AudiometryResult result) {
  final frequencies = result.frequencies;
  final byKey = {for (final t in result.thresholds) (t.ear, t.frequencyHz): t};
  return _table(
    [
      ['Frecuencia (Hz)', for (final f in frequencies) '$f'],
      for (final ear in Ear.values)
        [
          ear.label,
          for (final f in frequencies)
            switch (byKey[(ear, f)]) {
              null => '-',
              final t when t.noResponse => '>${t.thresholdDbHl} (SR)',
              final t => '${t.thresholdDbHl}',
            },
        ],
    ],
    // Fila 0 = encabezado; 1 = derecho; 2 = izquierdo.
    firstCellColors: {1: _earColor(Ear.right), 2: _earColor(Ear.left)},
  );
}

pw.Widget _summaryTable(AudiometryResult result) {
  return _table([
    ['Oído', 'Promedio tonal (PTA)', 'Clasificación (OMS)', 'Frecuencias del PTA (Hz)'],
    for (final ear in Ear.values)
      () {
        final s = summarizeEar(result, ear);
        final used = result
            .byEar(ear)
            .where((t) => ptaFrequenciesHz.contains(t.frequencyHz))
            .map((t) => t.frequencyHz)
            .join(', ');
        return [ear.label, s.ptaText, s.categoryLabel, used.isEmpty ? '-' : used];
      }(),
  ]);
}
