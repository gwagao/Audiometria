import 'package:flutter/material.dart';

import '../analysis.dart';
import '../app_state.dart';
import '../models.dart';
import 'result_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  Future<void> _delete(BuildContext context, AudiometryResult result) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar esta prueba?'),
        content: Text('${result.patient.name} · ${formatDateTime(result.performedAt)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed == true) await AppState.instance.deleteResult(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) {
          final history = AppState.instance.history;
          if (history.isEmpty) {
            return const Center(child: Text('Aún no hay pruebas guardadas.'));
          }
          return ListView.separated(
            itemCount: history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final result = history[i];
              final right = summarizeEar(result, Ear.right);
              final left = summarizeEar(result, Ear.left);
              return ListTile(
                leading: const Icon(Icons.assignment),
                title: Text(result.patient.name),
                subtitle: Text('${formatDateTime(result.performedAt)}\n'
                    'D: ${right.ptaText} · I: ${left.ptaText}'),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(context, result),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
