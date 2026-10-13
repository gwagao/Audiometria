import 'dart:math' as math;

/// Niveles de referencia (RETSPL, ANSI S3.6 / ISO 389-1, auricular supraaural):
/// dB SPL que corresponden a 0 dB HL en cada frecuencia.
const retsplDb = <int, double>{
  125: 45.0,
  250: 25.5,
  500: 11.5,
  750: 7.5,
  1000: 7.0,
  1500: 6.5,
  2000: 9.0,
  3000: 10.0,
  4000: 9.5,
  6000: 15.5,
  8000: 13.0,
};

/// Nivel (dB SPL) que se asume para un seno a escala completa con el volumen
/// multimedia al máximo. Es una aproximación para audífonos de consumo; el
/// ajuste de calibración del usuario corrige la diferencia real.
const fullScaleSplDb = 100.0;

/// Amplitud lineal (0..1) para presentar [dbHl] en [frequencyHz].
///
/// [offsetDb] es el nivel nominal al que una persona con audición normal apenas
/// percibe el tono de 1 kHz con estos audífonos (0 = sin corrección).
double amplitudeFor(int frequencyHz, num dbHl, {double offsetDb = 0}) {
  final dbfs = dbHl + offsetDb + retsplDb[frequencyHz]! - fullScaleSplDb;
  return math.pow(10, dbfs / 20).toDouble().clamp(0.0, 1.0);
}

/// Máximo nivel (dB HL, múltiplo de 5) reproducible sin saturar la salida.
int maxLevelFor(int frequencyHz, {double offsetDb = 0}) {
  final max = fullScaleSplDb - retsplDb[frequencyHz]! - offsetDb;
  return (max / 5).floor() * 5;
}
