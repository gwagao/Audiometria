import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Puente con el código nativo de Android (MainActivity.kt): generación de
/// tonos puros, detección de audífonos y control del volumen multimedia.
class AudioService {
  AudioService._();
  static final instance = AudioService._();

  static const _methods = MethodChannel('audiometria/audio');
  static const _deviceEvents = EventChannel('audiometria/devices');

  /// Dispositivo de salida actual; se actualiza al conectar o desconectar audífonos.
  final device = ValueNotifier<OutputDevice>(OutputDevice.speaker);

  bool _monitoring = false;

  /// Empieza a escuchar los cambios de dispositivo que emite Android.
  void startMonitoring() {
    if (_monitoring) return;
    _monitoring = true;
    _deviceEvents.receiveBroadcastStream().listen(
          (e) => device.value = OutputDevice.fromJson(e as Map<dynamic, dynamic>),
          onError: (_) {},
        );
  }

  /// Reproduce un tono puro en un solo oído ([ear] nulo = ambos).
  Future<void> playTone({
    required int frequencyHz,
    required double amplitude,
    required Ear? ear,
    required Duration duration,
  }) =>
      _methods.invokeMethod('playTone', {
        'frequency': frequencyHz.toDouble(),
        'amplitude': amplitude,
        'ear': ear?.name ?? 'both',
        'durationMs': duration.inMilliseconds,
      });

  Future<void> stopTone() => _methods.invokeMethod('stopTone');

  /// Sube el volumen multimedia al máximo (los niveles en dB lo suponen así).
  /// Devuelve `false` si el sistema no permitió llegar al máximo.
  Future<bool> setMaxVolume() async =>
      (await _methods.invokeMethod<bool>('setMaxVolume')) ?? false;

  /// Restaura el volumen que había antes de [setMaxVolume].
  Future<void> restoreVolume() => _methods.invokeMethod('restoreVolume');
}
