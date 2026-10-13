import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class Settings {
  const Settings({
    this.backendUrl = 'http://192.168.1.100:8000',
    this.calibrationOffsetDb = 0,
    this.maxLevelDbHl = 80,
    this.extendedFrequencies = false,
  });

  /// URL del backend Python (misma red Wi-Fi que el teléfono).
  final String backendUrl;
  final double calibrationOffsetDb;

  /// Tope de seguridad del nivel presentado.
  final int maxLevelDbHl;

  /// Añade 3000 y 6000 Hz a la prueba.
  final bool extendedFrequencies;

  /// Orden clínico habitual: empieza en 1 kHz, sube a agudos y termina en graves.
  List<int> get testFrequencies => extendedFrequencies
      ? const [1000, 2000, 3000, 4000, 6000, 8000, 500, 250]
      : const [1000, 2000, 4000, 8000, 500, 250];

  Settings copyWith({
    String? backendUrl,
    double? calibrationOffsetDb,
    int? maxLevelDbHl,
    bool? extendedFrequencies,
  }) =>
      Settings(
        backendUrl: backendUrl ?? this.backendUrl,
        calibrationOffsetDb: calibrationOffsetDb ?? this.calibrationOffsetDb,
        maxLevelDbHl: maxLevelDbHl ?? this.maxLevelDbHl,
        extendedFrequencies: extendedFrequencies ?? this.extendedFrequencies,
      );

  Map<String, dynamic> toJson() => {
        'backendUrl': backendUrl,
        'calibrationOffsetDb': calibrationOffsetDb,
        'maxLevelDbHl': maxLevelDbHl,
        'extendedFrequencies': extendedFrequencies,
      };

  factory Settings.fromJson(Map<String, dynamic> json) {
    const defaults = Settings();
    return Settings(
      backendUrl: (json['backendUrl'] as String?) ?? defaults.backendUrl,
      calibrationOffsetDb:
          (json['calibrationOffsetDb'] as num?)?.toDouble() ?? defaults.calibrationOffsetDb,
      maxLevelDbHl: (json['maxLevelDbHl'] as int?) ?? defaults.maxLevelDbHl,
      extendedFrequencies:
          (json['extendedFrequencies'] as bool?) ?? defaults.extendedFrequencies,
    );
  }
}

/// Ajustes e historial local, guardados en SharedPreferences.
class AppState extends ChangeNotifier {
  AppState._();
  static final instance = AppState._();

  static const _settingsKey = 'settings';
  static const _historyKey = 'history';

  late SharedPreferences _prefs;
  Settings settings = const Settings();

  /// Pruebas guardadas, la más reciente primero.
  List<AudiometryResult> history = [];

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final rawSettings = _prefs.getString(_settingsKey);
    if (rawSettings != null) {
      settings = Settings.fromJson(jsonDecode(rawSettings) as Map<String, dynamic>);
    }
    history = (_prefs.getStringList(_historyKey) ?? [])
        .map((s) => AudiometryResult.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  Future<void> updateSettings(Settings value) async {
    settings = value;
    notifyListeners();
    await _prefs.setString(_settingsKey, jsonEncode(value.toJson()));
  }

  /// Guarda [result]; si ya existe una prueba con la misma fecha, la reemplaza.
  Future<void> saveResult(AudiometryResult result) async {
    history = [
      result,
      ...history.where((r) => r.performedAt != result.performedAt),
    ];
    await _persistHistory();
  }

  Future<void> deleteResult(AudiometryResult result) async {
    history = history.where((r) => r.performedAt != result.performedAt).toList();
    await _persistHistory();
  }

  Future<void> _persistHistory() async {
    notifyListeners();
    await _prefs.setStringList(
      _historyKey,
      history.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }
}
