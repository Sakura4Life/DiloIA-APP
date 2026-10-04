import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

/// Pestaña "Calendario". En la fase 7 mostrará el mes con un color por curso.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icono: Icons.calendar_month,
      titulo: 'Tu mes de un vistazo',
      mensaje: 'Aquí verás tus entregas y exámenes, con un color por curso.',
    );
  }
}
