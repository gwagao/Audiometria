import 'package:flutter/material.dart';

import '../audio_service.dart';
import '../models.dart';

/// Muestra en vivo qué audífonos reconoce el teléfono.
class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<OutputDevice>(
      valueListenable: AudioService.instance.device,
      builder: (context, device, _) {
        final scheme = Theme.of(context).colorScheme;
        final ok = device.isHeadphones;
        final String detail;
        if (!ok) {
          detail = 'Conecta unos audífonos para realizar la prueba.';
        } else if (device.isBluetooth) {
          detail = '${device.typeLabel}. Para mayor precisión se recomiendan con cable.';
        } else {
          detail = device.typeLabel;
        }
        return Card(
          color: ok ? scheme.secondaryContainer : scheme.errorContainer,
          child: ListTile(
            leading: Icon(
              ok
                  ? (device.isBluetooth ? Icons.bluetooth_audio : Icons.headphones)
                  : Icons.headset_off,
              size: 32,
            ),
            title: Text(ok ? device.name : 'Sin audífonos detectados'),
            subtitle: Text(detail),
          ),
        );
      },
    );
  }
}
