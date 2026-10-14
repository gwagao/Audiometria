import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Cliente del backend Python (FastAPI).
class ApiClient {
  ApiClient(String baseUrl) : _base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  static const _timeout = Duration(seconds: 20);
  final String _base;

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'No se pudo conectar con el servidor en $_base. Verifica que el backend '
        'esté iniciado y que el teléfono esté en la misma red Wi-Fi.',
      );
    }
  }

  Future<bool> health() => _guard(() async {
        final r = await http.get(Uri.parse('$_base/health'));
        return r.statusCode == 200 &&
            (jsonDecode(r.body) as Map<String, dynamic>)['service'] == 'audiometria';
      });

  /// Guarda la prueba en el historial del backend; devuelve el id de la sesión.
  Future<String> saveSession(AudiometryResult result) => _guard(() async {
        final r = await http.post(
          Uri.parse('$_base/api/v1/sessions'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(result.toJson()),
        );
        if (r.statusCode != 201) {
          throw ApiException('El servidor rechazó la solicitud (HTTP ${r.statusCode}).');
        }
        return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
      });
}
