import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../audio_service.dart';
import '../calibration.dart';
import '../models.dart';
import '../threshold_search.dart';
import 'result_screen.dart';

/// Presenta los tonos puros y busca el umbral de cada oído y frecuencia.
class TestScreen extends StatefulWidget {
  const TestScreen({super.key, required this.patient});

  final Patient patient;

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> with WidgetsBindingObserver {
  static const _toneDuration = Duration(milliseconds: 1500);
  // Margen tras el final del tono en el que una pulsación aún cuenta como respuesta.
  static const _responseGrace = Duration(milliseconds: 700);
  static const _minSilenceMs = 1200;
  static const _silenceJitterMs = 1800;
  // Una segunda pulsación justo después de responder no es un falso positivo.
  static const _doubleTapGuard = Duration(milliseconds: 600);

  final _audio = AudioService.instance;
  final _settings = AppState.instance.settings;
  final _random = math.Random();
  final _thresholds = <ThresholdPoint>[];
  late final List<(Ear, int)> _steps = [
    for (final ear in Ear.values)
      for (final f in _settings.testFrequencies) (ear, f),
  ];
  late final OutputDevice _startDevice = _audio.device.value;

  late ThresholdSearch _search;
  int _stepIndex = 0;
  int _falsePositives = 0;
  bool _paused = false;
  String? _pauseReason;
  bool _pressFlash = false;

  // Cada ejecución del bucle tiene un número; al cambiarlo, el bucle anterior se detiene.
  int _generation = 0;
  Completer<void>? _response;
  bool _pressedInSilence = false;
  DateTime _lastResponse = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio.device.addListener(_onDeviceChanged);
    _search = _newSearch();
    _begin();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _audio.device.removeListener(_onDeviceChanged);
    _audio.stopTone().catchError((_) {});
    _audio.restoreVolume().catchError((_) {});
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause('La prueba se pausó al salir de la app.');
  }

  void _onDeviceChanged() {
    if (_startDevice.isHeadphones && !_audio.device.value.isHeadphones) {
      _pause('Se desconectaron los audífonos. Vuelve a conectarlos para continuar.');
    }
  }

  ThresholdSearch _newSearch() {
    final frequency = _steps[_stepIndex].$2;
    final reachable = maxLevelFor(frequency, offsetDb: _settings.calibrationOffsetDb);
    return ThresholdSearch(maxLevel: math.min(_settings.maxLevelDbHl, reachable));
  }

  Future<void> _begin() async {
    try {
      final atMax = await _audio.setMaxVolume();
      if (!atMax && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 6),
          content: Text('El teléfono limitó el volumen. Súbelo al máximo manualmente '
              'para que los niveles sean correctos.'),
        ));
      }
    } on MissingPluginException {
      _pause('El audio solo está disponible en Android.');
      return;
    } on PlatformException catch (e) {
      _pause('No se pudo preparar el audio: ${e.message}');
      return;
    }
    _run(++_generation);
  }

  Future<void> _run(int generation) async {
    bool cancelled() => !mounted || generation != _generation;

    while (_stepIndex < _steps.length) {
      // Silencio de duración aleatoria para que el paciente no anticipe el tono.
      _pressedInSilence = false;
      await Future.delayed(
          Duration(milliseconds: _minSilenceMs + _random.nextInt(_silenceJitterMs)));
      if (cancelled()) return;
      if (_pressedInSilence) continue;

      final (ear, frequency) = _steps[_stepIndex];
      final response = _response = Completer<void>();
      try {
        await _audio.playTone(
          frequencyHz: frequency,
          amplitude: amplitudeFor(frequency, _search.level,
              offsetDb: _settings.calibrationOffsetDb),
          ear: ear,
          duration: _toneDuration,
        );
      } on PlatformException catch (e) {
        _response = null;
        _pause('Error de audio: ${e.message}');
        return;
      }
      final heard = await Future.any([
        response.future.then((_) => true),
        Future.delayed(_toneDuration + _responseGrace, () => false),
      ]);
      _response = null;
      if (cancelled()) return;
      if (heard) await _audio.stopTone();

      _search.record(heard);
      if (_search.done) {
        _thresholds.add(ThresholdPoint(
          ear: ear,
          frequencyHz: frequency,
          thresholdDbHl: _search.threshold,
          noResponse: _search.noResponse,
        ));
        _stepIndex++;
        if (_stepIndex < _steps.length) _search = _newSearch();
        setState(() {});
      }
    }
    await _finish();
  }

  void _onHeardPressed() {
    setState(() => _pressFlash = true);
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _pressFlash = false);
    });

    final response = _response;
    final now = DateTime.now();
    if (response != null && !response.isCompleted) {
      _lastResponse = now;
      response.complete();
    } else if (now.difference(_lastResponse) > _doubleTapGuard && !_paused) {
      _falsePositives++;
      _pressedInSilence = true;
    }
  }

  void _pause(String reason) {
    if (_paused || _stepIndex >= _steps.length) return;
    _generation++;
    _response = null;
    _audio.stopTone().catchError((_) {});
    if (mounted) {
      setState(() {
        _paused = true;
        _pauseReason = reason;
      });
    }
  }

  void _resume() {
    setState(() {
      _paused = false;
      _pauseReason = null;
    });
    // La presentación interrumpida no se registró, así que se repite al mismo nivel.
    _begin();
  }

  Future<void> _finish() async {
    final result = AudiometryResult(
      patient: widget.patient,
      performedAt: DateTime.now(),
      device: _startDevice.withCalibration(_settings.calibrationOffsetDb),
      thresholds: List.unmodifiable(_thresholds),
      falsePositives: _falsePositives,
    );
    await AppState.instance.saveResult(result);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }

  Future<void> _confirmExit() async {
    final wasPaused = _paused;
    _pause('Prueba en pausa.');
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar la prueba?'),
        content: const Text('Se perderá el progreso de esta prueba.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Seguir')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancelar prueba')),
        ],
      ),
    );
    if (!mounted) return;
    if (exit == true) {
      Navigator.of(context).pop();
    } else if (!wasPaused && _audio.device.value.isHeadphones == _startDevice.isHeadphones) {
      _resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final index = math.min(_stepIndex, _steps.length - 1);
    final ear = _steps[index].$1;
    final perEar = _settings.testFrequencies.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Prueba en curso'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _confirmExit),
          actions: [
            if (!_paused)
              IconButton(
                tooltip: 'Pausar',
                icon: const Icon(Icons.pause),
                onPressed: () => _pause('Prueba en pausa.'),
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: _stepIndex / _steps.length, minHeight: 8),
                const SizedBox(height: 16),
                Text(ear.label,
                    textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                Text('Tono ${index % perEar + 1} de $perEar',
                    textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                if (_paused) ...[
                  Card(
                    color: scheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_pauseReason ?? 'Prueba en pausa.',
                          textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Continuar'),
                    onPressed: _resume,
                  ),
                ] else
                  Text(
                    'Pulsa el botón cada vez que escuches un tono,\naunque sea muy débil.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                const Spacer(),
                SizedBox(
                  height: 220,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: _pressFlash ? scheme.primaryContainer : scheme.primary,
                      foregroundColor: _pressFlash ? scheme.onPrimaryContainer : scheme.onPrimary,
                    ),
                    onPressed: _paused ? null : _onHeardPressed,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hearing, size: 56),
                        const SizedBox(height: 8),
                        Text('Lo escucho',
                            style: theme.textTheme.titleLarge!.copyWith(color: null)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
