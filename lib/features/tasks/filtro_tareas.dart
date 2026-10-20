import 'package:flutter/material.dart';

import '../../data/database.dart';

/// Momento en que una tarea "pasa": la hora límite de una entrega, o la hora
/// en que termina un evento (un examen de 4 a 6 sigue pendiente hasta las 6).
DateTime finDeTarea(Task tarea) => tarea.tipo.esPlazo
    ? tarea.inicio
    : tarea.inicio.add(Duration(minutes: tarea.duracionMinutos));

/// Si la tarea ya pasó (ver [finDeTarea]).
bool yaPaso(Task tarea, {required DateTime ahora}) =>
    !finDeTarea(tarea).isAfter(ahora);

/// Qué tareas muestra la lista. La app empieza en "Pendientes" y el botón de
/// filtro recorre los estados en este orden y vuelve a empezar:
/// Pendientes → Completadas → Pasadas → Todas → Pendientes…
enum FiltroTareas {
  pendientes('Pendientes', Icons.radio_button_unchecked, 'Sin pendientes'),
  completadas('Completadas', Icons.check, 'Sin tareas completadas'),
  pasadas('Pasadas', Icons.history, 'Sin tareas pasadas'),
  todas('Todas', Icons.list_alt, 'Sin tareas');

  const FiltroTareas(this.etiqueta, this.icono, this.mensajeVacio);

  final String etiqueta;
  final IconData icono;

  /// Título de la pantalla vacía cuando el filtro no deja ninguna tarea.
  final String mensajeVacio;

  /// El estado que sigue al tocar el botón.
  FiltroTareas get siguiente => values[(index + 1) % values.length];

  /// Si [tarea] se muestra con este filtro.
  ///
  /// - Pendientes: sin completar y que todavía no pasan.
  /// - Completadas: las marcadas, de cualquier fecha.
  /// - Pasadas: las que ya pasaron, completadas o no.
  bool incluye(Task tarea, {required DateTime ahora}) => switch (this) {
    pendientes => !tarea.completada && !yaPaso(tarea, ahora: ahora),
    completadas => tarea.completada,
    pasadas => yaPaso(tarea, ahora: ahora),
    todas => true,
  };
}
