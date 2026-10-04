import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

/// Pestaña "Panel". En la fase 7 mostrará el porcentaje de la nota en juego
/// cada semana.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icono: Icons.insights,
      titulo: 'Carga semanal',
      mensaje:
          'Aquí verás qué porcentaje de tu nota está en juego cada semana.',
    );
  }
}
