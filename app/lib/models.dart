enum Ear { right, left }

extension EarLabels on Ear {
  String get label => this == Ear.right ? 'Oído derecho' : 'Oído izquierdo';
  String get shortLabel => this == Ear.right ? 'Derecho' : 'Izquierdo';
}

class Patient {
  const Patient({required this.name, this.age, this.sex, this.document});

  final String name;
  final int? age;

  /// 'M', 'F' u 'O'.
  final String? sex;
  final String? document;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (age != null) 'age': age,
        if (sex != null) 'sex': sex,
        if (document != null && document!.isNotEmpty) 'document': document,
      };

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        name: json['name'] as String,
        age: json['age'] as int?,
        sex: json['sex'] as String?,
        document: json['document'] as String?,
      );
}

/// Salida de audio detectada en el teléfono.
class OutputDevice {
  const OutputDevice({
    required this.name,
    required this.type,
    this.calibrationOffsetDb = 0,
  });

  static const speaker = OutputDevice(name: 'Altavoz del teléfono', type: 'speaker');

  final String name;

  /// 'wired', 'usb', 'bluetooth', 'hearing_aid' o 'speaker'.
  final String type;
  final double calibrationOffsetDb;

  bool get isHeadphones => type != 'speaker';
  bool get isBluetooth => type == 'bluetooth' || type == 'hearing_aid';

  String get typeLabel => switch (type) {
        'wired' => 'Audífonos con cable',
        'usb' => 'Audífonos USB',
        'bluetooth' => 'Audífonos Bluetooth',
        'hearing_aid' => 'Audífono médico',
        _ => 'Altavoz del teléfono',
      };

  OutputDevice withCalibration(double offsetDb) =>
      OutputDevice(name: name, type: type, calibrationOffsetDb: offsetDb);

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'calibration_offset_db': calibrationOffsetDb,
      };

  factory OutputDevice.fromJson(Map<dynamic, dynamic> json) => OutputDevice(
        name: (json['name'] as String?) ?? 'Desconocido',
        type: (json['type'] as String?) ?? 'speaker',
        calibrationOffsetDb: (json['calibration_offset_db'] as num?)?.toDouble() ?? 0,
      );
}

class ThresholdPoint {
  const ThresholdPoint({
    required this.ear,
    required this.frequencyHz,
    required this.thresholdDbHl,
    this.noResponse = false,
  });

  final Ear ear;
  final int frequencyHz;
  final int thresholdDbHl;

  /// Sin respuesta al nivel máximo; [thresholdDbHl] es ese máximo.
  final bool noResponse;

  Map<String, dynamic> toJson() => {
        'ear': ear.name,
        'frequency_hz': frequencyHz,
        'threshold_db_hl': thresholdDbHl,
        'no_response': noResponse,
      };

  factory ThresholdPoint.fromJson(Map<String, dynamic> json) => ThresholdPoint(
        ear: Ear.values.byName(json['ear'] as String),
        frequencyHz: json['frequency_hz'] as int,
        thresholdDbHl: (json['threshold_db_hl'] as num).round(),
        noResponse: (json['no_response'] as bool?) ?? false,
      );
}

class AudiometryResult {
  const AudiometryResult({
    required this.patient,
    required this.performedAt,
    required this.device,
    required this.thresholds,
    this.method = 'Hughson-Westlake modificado',
    this.falsePositives = 0,
    this.notes,
  });

  final Patient patient;
  final DateTime performedAt;
  final OutputDevice device;
  final String method;
  final List<ThresholdPoint> thresholds;
  final int falsePositives;
  final String? notes;

  List<ThresholdPoint> byEar(Ear ear) =>
      thresholds.where((t) => t.ear == ear).toList()
        ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));

  List<int> get frequencies =>
      thresholds.map((t) => t.frequencyHz).toSet().toList()..sort();

  AudiometryResult withNotes(String? notes) => AudiometryResult(
        patient: patient,
        performedAt: performedAt,
        device: device,
        thresholds: thresholds,
        method: method,
        falsePositives: falsePositives,
        notes: notes,
      );

  /// Mismo formato que espera el backend (app/schemas.py).
  Map<String, dynamic> toJson() => {
        'patient': patient.toJson(),
        'performed_at': performedAt.toIso8601String(),
        'device': device.toJson(),
        'method': method,
        'thresholds': thresholds.map((t) => t.toJson()).toList(),
        'false_positives': falsePositives,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  factory AudiometryResult.fromJson(Map<String, dynamic> json) => AudiometryResult(
        patient: Patient.fromJson(json['patient'] as Map<String, dynamic>),
        performedAt: DateTime.parse(json['performed_at'] as String),
        device: OutputDevice.fromJson(json['device'] as Map<String, dynamic>),
        method: (json['method'] as String?) ?? 'Hughson-Westlake modificado',
        thresholds: (json['thresholds'] as List)
            .map((t) => ThresholdPoint.fromJson(t as Map<String, dynamic>))
            .toList(),
        falsePositives: (json['false_positives'] as int?) ?? 0,
        notes: json['notes'] as String?,
      );
}

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
