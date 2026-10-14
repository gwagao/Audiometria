import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../audio_service.dart';
import '../calibration.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _state = AppState.instance;
  late final _url = TextEditingController(text: _state.settings.backendUrl);
  late double _offset = _state.settings.calibrationOffsetDb;
  late int _maxLevel = _state.settings.maxLevelDbHl;
  late bool _extended = _state.settings.extendedFrequencies;
  bool _checking = false;
  bool _volumeRaised = false;

  @override
  void dispose() {
    _url.dispose();
    if (_volumeRaised) AudioService.instance.restoreVolume().catchError((_) {});
    super.dispose();
  }

  Future<void> _save() => _state.updateSettings(_state.settings.copyWith(
        backendUrl: _url.text.trim(),
        calibrationOffsetDb: _offset,
        maxLevelDbHl: _maxLevel,
        extendedFrequencies: _extended,
      ));

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _checkConnection() async {
    setState(() => _checking = true);
    await _save();
    try {
      final ok = await ApiClient(_url.text).health();
      _message(ok ? 'Conexión correcta con el servidor.' : 'El servidor respondió, '
          'pero no es el backend de Audiometría.');
    } on ApiException catch (e) {
      _message(e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Reproduce el tono de 1 kHz que, con el ajuste actual, equivale a 0 dB HL.
  Future<void> _playCalibrationTone() async {
    try {
      // Igual que en la prueba: los niveles suponen el volumen al máximo.
      _volumeRaised = true;
      await AudioService.instance.setMaxVolume();
      await AudioService.instance.playTone(
        frequencyHz: 1000,
        amplitude: amplitudeFor(1000, 0, offsetDb: _offset),
        ear: null,
        duration: const Duration(milliseconds: 2000),
      );
    } on PlatformException catch (e) {
      _message('No se pudo reproducir el tono: ${e.message}');
    } on MissingPluginException {
      _message('El audio solo está disponible en Android.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Servidor (opcional)', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('El PDF se genera en el teléfono. El servidor solo se usa para '
                'guardar una copia de las pruebas en el computador.'),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'URL del backend',
                hintText: 'http://192.168.1.100:8000',
                helperText: 'IP del computador donde corre el backend Python.',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
              onTapOutside: (_) {
                FocusScope.of(context).unfocus();
                _save();
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: _checking
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Probar conexión'),
              onPressed: _checking ? null : _checkConnection,
            ),
            const Divider(height: 36),
            Text('Calibración de los audífonos', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'En un lugar silencioso, una persona con audición normal debe mover el '
              'control hasta que el tono de 1 kHz apenas se escuche. Ese punto será el '
              '0 dB HL para estos audífonos.',
            ),
            Slider(
              value: _offset,
              min: -30,
              max: 30,
              divisions: 60,
              label: '${_offset.toStringAsFixed(0)} dB',
              onChanged: (v) => setState(() => _offset = v),
              onChangeEnd: (_) => _save(),
            ),
            Row(
              children: [
                Expanded(child: Text('Ajuste: ${_offset.toStringAsFixed(0)} dB')),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Reproducir tono'),
                  onPressed: _playCalibrationTone,
                ),
              ],
            ),
            const Divider(height: 36),
            Text('Prueba', style: theme.textTheme.titleMedium),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nivel máximo'),
              subtitle: const Text('Tope de seguridad de los tonos presentados.'),
              trailing: DropdownButton<int>(
                value: _maxLevel,
                items: const [
                  DropdownMenuItem(value: 70, child: Text('70 dB HL')),
                  DropdownMenuItem(value: 80, child: Text('80 dB HL')),
                  DropdownMenuItem(value: 90, child: Text('90 dB HL')),
                ],
                onChanged: (v) {
                  setState(() => _maxLevel = v!);
                  _save();
                },
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Frecuencias extendidas'),
              subtitle: const Text('Añade 3000 y 6000 Hz (la prueba dura más).'),
              value: _extended,
              onChanged: (v) {
                setState(() => _extended = v);
                _save();
              },
            ),
          ],
        ),
      ),
    );
  }
}
