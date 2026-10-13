import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../audio_service.dart';
import '../calibration.dart';
import '../models.dart';
import '../widgets/device_card.dart';
import 'test_screen.dart';

/// Datos del paciente y comprobaciones previas a la prueba.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _document = TextEditingController();
  String? _sex;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _document.dispose();
    super.dispose();
  }

  Future<void> _playCheck(Ear ear) async {
    final offset = AppState.instance.settings.calibrationOffsetDb;
    try {
      await AudioService.instance.playTone(
        frequencyHz: 1000,
        amplitude: amplitudeFor(1000, 50, offsetDb: offset),
        ear: ear,
        duration: const Duration(milliseconds: 1000),
      );
    } on PlatformException catch (e) {
      _showMessage('No se pudo reproducir el tono: ${e.message}');
    } on MissingPluginException {
      _showMessage('El audio solo está disponible en Android.');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;
    if (!AudioService.instance.device.value.isHeadphones) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sin audífonos'),
          content: const Text(
            'No se detectaron audífonos. Sin ellos no es posible evaluar cada oído '
            'por separado y el resultado no será válido. ¿Continuar de todos modos?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    final document = _document.text.trim();
    final patient = Patient(
      name: _name.text.trim(),
      age: int.tryParse(_age.text),
      sex: _sex,
      document: document.isEmpty ? null : document,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TestScreen(patient: patient)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva prueba')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Paciente', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                decoration: const InputDecoration(
                    labelText: 'Nombre completo', border: OutlineInputBorder(), counterText: ''),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa el nombre del paciente' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                          labelText: 'Edad', border: OutlineInputBorder()),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final age = int.tryParse(v);
                        return (age == null || age > 120) ? 'Edad no válida' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _sex,
                      decoration: const InputDecoration(
                          labelText: 'Sexo', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'F', child: Text('Femenino')),
                        DropdownMenuItem(value: 'M', child: Text('Masculino')),
                        DropdownMenuItem(value: 'O', child: Text('Otro')),
                      ],
                      onChanged: (v) => setState(() => _sex = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _document,
                maxLength: 40,
                decoration: const InputDecoration(
                    labelText: 'Documento (opcional)',
                    border: OutlineInputBorder(),
                    counterText: ''),
              ),
              const SizedBox(height: 20),
              Text('Audífonos', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              const DeviceCard(),
              const SizedBox(height: 8),
              const Text('Comprueba que cada audífono esté en el oído correcto:'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.volume_up),
                      label: const Text('Izquierdo'),
                      onPressed: () => _playCheck(Ear.left),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.volume_up),
                      label: const Text('Derecho'),
                      onPressed: () => _playCheck(Ear.right),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Antes de empezar', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const _Tip('Busca un lugar silencioso.'),
              const _Tip('El volumen se ajustará al máximo automáticamente; no lo cambies.'),
              const _Tip('Los tonos empiezan suaves y van subiendo de intensidad.'),
              const _Tip('Pulsa «Lo escucho» cada vez que oigas un tono, aunque sea muy débil.'),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(18)),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Comenzar prueba'),
                onPressed: _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
