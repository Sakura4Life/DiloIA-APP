import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/database.dart';

/// Una tarea que todavía se está llenando en el formulario. Todos los campos
/// pueden faltar. En la fase 4, la IA devolverá un borrador como este a partir
/// del dictado, y el usuario lo completará o corregirá antes de guardar.
class BorradorTarea {
  BorradorTarea({
    this.courseId,
    this.tipo,
    this.titulo,
    this.fecha,
    this.hora,
    this.duracion,
    this.peso,
  });

  /// Borrador con los datos de una tarea ya guardada, para editarla.
  factory BorradorTarea.desdeTarea(Task tarea) {
    final duracion = Duration(minutes: tarea.duracionMinutos);
    return BorradorTarea(
      courseId: tarea.courseId,
      tipo: tarea.tipo,
      titulo: tarea.titulo,
      fecha: tarea.inicio,
      hora: TimeOfDay.fromDateTime(tarea.inicio),
      // Solo se guarda si el usuario la había cambiado: así, si ahora cambia
      // el tipo, toma la duración del tipo nuevo.
      duracion: tarea.tipo.esPlazo || duracion == tarea.tipo.duracionPorDefecto
          ? null
          : duracion,
      peso: tarea.pesoPorcentaje,
    );
  }

  int? courseId;
  TipoActividad? tipo;

  /// Opcional, por ejemplo "Laboratorio 3".
  String? titulo;

  /// Solo importa el día; la hora va aparte en [hora].
  DateTime? fecha;
  TimeOfDay? hora;

  /// Duración elegida por el usuario (o entendida por la IA). Si es `null`,
  /// se usa la del tipo. Los plazos no tienen duración.
  Duration? duracion;
  double? peso;

  /// La duración que se guardará: la elegida, la del tipo, o cero en los
  /// plazos (entrega y proyecto).
  Duration get duracionFinal {
    final t = tipo;
    if (t == null || t.esPlazo) return Duration.zero;
    return duracion ?? t.duracionPorDefecto;
  }

  /// Cuándo termina, si es un evento con fecha y hora. `null` en los plazos.
  DateTime? get fin {
    final momento = inicio;
    final t = tipo;
    if (momento == null || t == null || t.esPlazo) return null;
    return momento.add(duracionFinal);
  }

  /// Campos obligatorios que faltan, en el orden en que aparecen en pantalla.
  List<String> get faltantes => [
    if (courseId == null) 'curso',
    if (tipo == null) 'tipo',
    if (fecha == null) 'fecha',
    if (hora == null) 'hora',
  ];

  bool get estaCompleto => faltantes.isEmpty;

  /// Verdadero si la fecha y hora elegidas ya pasaron. Si se está editando una
  /// tarea y no se cambió su momento ([inicioOriginal]), no cuenta: así se
  /// puede editar una tarea vencida, por ejemplo para corregir su título.
  bool yaPaso({required DateTime ahora, DateTime? inicioOriginal}) {
    final momento = inicio;
    if (momento == null || momento == inicioOriginal) return false;
    return momento.isBefore(ahora);
  }

  /// Fecha y hora juntas, o `null` si falta alguna de las dos.
  DateTime? get inicio {
    final f = fecha;
    final h = hora;
    if (f == null || h == null) return null;
    return DateTime(f.year, f.month, f.day, h.hour, h.minute);
  }
}

/// Convierte el texto del campo "peso" en número. Acepta coma o punto decimal.
/// Devuelve `null` si está vacío o no es un número.
double? leerPeso(String texto) {
  final limpio = texto.trim().replaceAll(',', '.');
  if (limpio.isEmpty) return null;
  return double.tryParse(limpio);
}

/// Mensaje de error del campo "peso", o `null` si es válido. El peso es
/// opcional: vacío también es válido.
String? validarPeso(String texto) {
  if (texto.trim().isEmpty) return null;
  final peso = leerPeso(texto);
  if (peso == null) return 'Escribe solo el número, por ejemplo 20';
  if (peso < 0 || peso > 100) return 'Debe estar entre 0 y 100';
  return null;
}
