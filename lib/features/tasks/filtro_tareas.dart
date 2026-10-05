import 'package:flutter/material.dart';

import '../../data/database.dart';

/// Qué tareas muestra la lista. Se cambia tocando el botón de filtro, que
/// recorre los estados en este orden y vuelve a empezar:
/// Todas → Pendientes → Completadas → Pasadas → Todas…
enum FiltroTareas {
  todas('Todas', Icons.list_alt, 'Sin tareas'),
  pendientes('Pendientes', Icons.radio_button_unchecked, 'Sin pendientes'),
  completadas('Completadas', Icons.check, 'Sin tareas completadas'),
  pasadas('Pasadas', Icons.history, 'Sin tareas pasadas');

  const FiltroTareas(this.etiqueta, this.icono, this.mensajeVacio);

  final String etiqueta;
  final IconData icono;

  /// Título de la pantalla vacía cuando el filtro no deja ninguna tarea.
  final String mensajeVacio;

  /// El estado que sigue al tocar el botón.
  FiltroTareas get siguiente => values[(index + 1) % values.length];

  /// Si [tarea] se muestra con este filtro.
  ///
  /// - Pendientes: las no completadas, incluidas las vencidas.
  /// - Pasadas: las que ya pasaron de fecha, completadas o no.
  bool incluye(Task tarea, {required DateTime ahora}) => switch (this) {
    todas => true,
    pendientes => !tarea.completada,
    completadas => tarea.completada,
    pasadas => tarea.inicio.isBefore(ahora),
  };
}
