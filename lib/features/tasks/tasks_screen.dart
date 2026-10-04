import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/empty_state.dart';

/// Pestaña "Pendientes". En la fase 2 mostrará la lista de tareas guardadas.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Ej.: "sábado, 3 de octubre". El idioma lo fija Intl.defaultLocale.
    final hoy = DateFormat("EEEE, d 'de' MMMM").format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Hoy es $hoy',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Expanded(
          child: EmptyState(
            icono: Icons.task_alt,
            titulo: 'Sin pendientes',
            mensaje:
                'Mantén presionado el micrófono y dicta tu primera tarea.\n'
                'Por ejemplo: «examen de física a las 8, vale 30%».',
          ),
        ),
      ],
    );
  }
}
