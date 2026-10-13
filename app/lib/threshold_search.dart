import 'dart:math' as math;

/// Búsqueda de umbral con el método Hughson-Westlake modificado:
/// el tono sube hasta que el paciente responde; luego baja 10 dB tras cada
/// respuesta y sube 5 dB tras cada silencio. El umbral es el nivel más bajo
/// con 2 respuestas en presentaciones ascendentes.
class ThresholdSearch {
  ThresholdSearch({
    this.startLevel = 30,
    this.minLevel = -10,
    required this.maxLevel,
    this.maxTrials = 30,
  })  : assert(minLevel <= maxLevel),
        level = startLevel.clamp(minLevel, maxLevel);

  static const initialStepUp = 10;
  static const stepUp = 5;
  static const stepDown = 10;
  static const requiredHits = 2;

  final int startLevel;
  final int minLevel;
  final int maxLevel;
  final int maxTrials;

  /// Nivel (dB HL) de la próxima presentación.
  int level;

  int? _threshold;
  bool _noResponse = false;
  bool _ascending = false;
  bool _everHeard = false;
  int _trials = 0;
  int _missesAtMax = 0;
  int? _lowestHeard;
  final _ascendingHits = <int, int>{};

  bool get done => _threshold != null;
  int get threshold => _threshold!;
  bool get noResponse => _noResponse;
  int get trials => _trials;

  /// Registra si el paciente respondió al tono presentado en [level].
  void record(bool heard) {
    if (done) throw StateError('La búsqueda ya terminó');
    _trials++;

    if (heard) {
      _everHeard = true;
      _lowestHeard = math.min(_lowestHeard ?? level, level);
      // En el nivel mínimo no se puede bajar más, así que toda respuesta cuenta.
      if (_ascending || level == minLevel) {
        final hits = (_ascendingHits[level] ?? 0) + 1;
        _ascendingHits[level] = hits;
        if (hits >= requiredHits) return _finish(level, noResponse: false);
      }
      level = math.max(level - stepDown, minLevel);
      _ascending = false;
    } else {
      if (level >= maxLevel) {
        if (++_missesAtMax >= 2) return _finish(maxLevel, noResponse: true);
      } else {
        level = math.min(level + (_everHeard ? stepUp : initialStepUp), maxLevel);
      }
      _ascending = true;
    }

    if (_trials >= maxTrials) {
      // Respuestas inconsistentes: se toma la mejor estimación disponible.
      _finish(_lowestHeard ?? maxLevel, noResponse: _lowestHeard == null);
    }
  }

  void _finish(int value, {required bool noResponse}) {
    _threshold = value;
    _noResponse = noResponse;
  }
}
