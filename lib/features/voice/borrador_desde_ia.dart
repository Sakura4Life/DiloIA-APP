import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/database.dart';
import '../tasks/task_draft.dart';
import 'extraccion_api.dart';

/// Lo que se le muestra al usuario en la tarjeta después de dictar.
typedef BorradorDeVoz = ({
  BorradorTarea borrador,

  /// Curso que se dictó pero no existe todavía, para ofrecer crearlo. Es
  /// `null` si se reconoció el curso o si no se dijo ninguno.
  String? materiaNueva,
});

/// Convierte lo que entendió la IA en un borrador para la tarjeta.
///
/// Es una función pura (no usa la base de datos ni la pantalla), así que se
/// puede probar fácilmente. [ahora] se recibe como parámetro por lo mismo.
BorradorDeVoz borradorDesdeIA(
  ResultadoIA resultado, {
  required List<Course> cursos,
  required DateTime ahora,
}) {
  // La función ya devuelve el nombre exacto si coincide; se vuelve a comparar
  // ignorando tildes y mayúsculas por si el curso se renombró mientras el
  // dictado esperaba en la cola.
  final materia = resultado.materia;
  final curso = materia == null
      ? null
      : cursos
            .where((c) => claveDeOrden(c.nombre) == claveDeOrden(materia))
            .firstOrNull;

  final peso = resultado.peso;
  final titulo = resultado.titulo;
  return (
    borrador: BorradorTarea(
      courseId: curso?.id,
      tipo:
          TipoActividad.values.asNameMap()[resultado.tipo] ??
          TipoActividad.otro,
      titulo: titulo == null || titulo.length > 80 ? null : titulo,
      fecha: _fechaFutura(resultado.fecha, ahora),
      hora: _leerHora(resultado.hora),
      peso: peso != null && peso >= 0 && peso <= 100 ? peso : null,
    ),
    materiaNueva: curso == null ? materia : null,
  );
}

/// "2026-10-09" → 9 de octubre de 2026. Si el día ya pasó (por ejemplo, un
/// dictado que esperó días sin internet) se deja vacío para que el usuario
/// elija otro: la tarjeta no permite guardar fechas pasadas.
DateTime? _fechaFutura(String? texto, DateTime ahora) {
  if (texto == null) return null;
  final fecha = DateTime.tryParse(texto);
  if (fecha == null) return null;
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  return dia.isBefore(hoy) ? null : dia;
}

/// "16:30" → 4:30 p. m.
TimeOfDay? _leerHora(String? texto) {
  final partes = texto?.split(':');
  if (partes == null || partes.length != 2) return null;
  final hora = int.tryParse(partes[0]);
  final minuto = int.tryParse(partes[1]);
  if (hora == null || minuto == null) return null;
  if (hora < 0 || hora > 23 || minuto < 0 || minuto > 59) return null;
  return TimeOfDay(hour: hora, minute: minuto);
}
