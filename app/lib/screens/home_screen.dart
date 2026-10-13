import 'package:flutter/material.dart';

import '../widgets/device_card.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audiometría'),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings),
            onPressed: () => _open(context, const SettingsScreen()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Icon(Icons.hearing, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text('Prueba de audición con tonos puros',
                textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            const DeviceCard(),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(18)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Nueva prueba'),
              onPressed: () => _open(context, const SetupScreen()),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(18)),
              icon: const Icon(Icons.history),
              label: const Text('Historial'),
              onPressed: () => _open(context, const HistoryScreen()),
            ),
            const SizedBox(height: 28),
            Text(
              'Esta aplicación es una herramienta de cribado orientativa y no '
              'sustituye una audiometría clínica realizada por un profesional.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
