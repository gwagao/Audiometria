import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../analysis.dart';
import '../api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../pdf_report.dart';
import '../widgets/audiogram_chart.dart';

/// Audiograma, resumen y opciones para generar el PDF y compartir.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.result});

  final AudiometryResult result;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late AudiometryResult _result = widget.result;
  late final _notes = TextEditingController(text: widget.result.notes ?? '');
  bool _busy = false;
  bool _uploading = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    final notes = _notes.text.trim();
    if (notes == (_result.notes ?? '')) return;
    _result = _result.withNotes(notes.isEmpty ? null : notes);
    await AppState.instance.saveResult(_result);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6)));
  }

  Future<void> _sharePdf() async {
    setState(() => _busy = true);
    try {
      await _saveNotes();
      final file = await saveReportPdf(_result);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Audiometría de ${_result.patient.name}',
        text: 'Informe de audiometría de ${_result.patient.name} '
            '(${formatDateTime(_result.performedAt)}).',
      ));
    } catch (e) {
      _message('No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opcional: guarda una copia en el historial del backend Python.
  Future<void> _uploadToServer() async {
    setState(() => _uploading = true);
    try {
      await _saveNotes();
      await ApiClient(AppState.instance.settings.backendUrl).saveSession(_result);
      _message('Copia guardada en el servidor.');
    } on ApiException catch (e) {
      _message(e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _shareText() async {
    await _saveNotes();
    await SharePlus.instance.share(ShareParams(
      text: summaryText(_result),
      subject: 'Audiometría de ${_result.patient.name}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patient = _result.patient;
    final details = [
      if (patient.age != null) '${patient.age} años',
      formatDateTime(_result.performedAt),
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: const Text('Resultado')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(patient.name, style: theme.textTheme.titleLarge),
            Text(details, style: theme.textTheme.bodyMedium),
            Text('${_result.device.name} · ${_result.device.typeLabel}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            AudiogramChart(thresholds: _result.thresholds),
            const SizedBox(height: 16),
            for (final ear in Ear.values) _EarSummaryCard(summarizeEar(_result, ear)),
            const SizedBox(height: 8),
            _ThresholdTable(_result),
            if (_result.falsePositives > 0) ...[
              const SizedBox(height: 8),
              Text('Respuestas sin tono presente: ${_result.falsePositives}',
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Notas para el informe (opcional)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onTapOutside: (_) {
                FocusScope.of(context).unfocus();
                _saveNotes();
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              icon: _busy
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf),
              label: Text(_busy ? 'Generando informe…' : 'Generar PDF y compartir'),
              onPressed: _busy ? null : _sharePdf,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
              icon: const Icon(Icons.share),
              label: const Text('Compartir resumen en texto'),
              onPressed: _shareText,
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              icon: _uploading
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('Guardar copia en el servidor (opcional)'),
              onPressed: _uploading ? null : _uploadToServer,
            ),
            const SizedBox(height: 16),
            Text(
              'Resultado orientativo obtenido con audífonos sin calibración certificada. '
              'No constituye un diagnóstico médico.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EarSummaryCard extends StatelessWidget {
  const _EarSummaryCard(this.summary);

  final EarSummary summary;

  @override
  Widget build(BuildContext context) {
    final earColor = summary.ear == Ear.right ? rightEarColor : leftEarColor;
    final category = summary.category;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: earColor,
          foregroundColor: Colors.white,
          child: Text(summary.ear == Ear.right ? 'D' : 'I'),
        ),
        title: Text(summary.categoryLabel,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: category == null ? null : Color(category.color))),
        subtitle: Text('${summary.ear.label} · Promedio tonal: ${summary.ptaText}'),
      ),
    );
  }
}

class _ThresholdTable extends StatelessWidget {
  const _ThresholdTable(this.result);

  final AudiometryResult result;

  @override
  Widget build(BuildContext context) {
    final byKey = {for (final t in result.thresholds) (t.ear, t.frequencyHz): t};
    String cell(Ear ear, int frequency) {
      final t = byKey[(ear, frequency)];
      if (t == null) return '—';
      return '${t.noResponse ? '>' : ''}${t.thresholdDbHl}';
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 36,
        columns: [
          const DataColumn(label: Text('Hz')),
          for (final f in result.frequencies) DataColumn(label: Text('$f'), numeric: true),
        ],
        rows: [
          for (final ear in Ear.values)
            DataRow(cells: [
              DataCell(Text(ear.shortLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: ear == Ear.right ? rightEarColor : leftEarColor))),
              for (final f in result.frequencies) DataCell(Text(cell(ear, f))),
            ]),
        ],
      ),
    );
  }
}
