import 'package:flutter/material.dart';

import 'app_state.dart';
import 'audio_service.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.load();
  AudioService.instance.startMonitoring();
  runApp(const AudiometriaApp());
}

class AudiometriaApp extends StatelessWidget {
  const AudiometriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audiometría',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
