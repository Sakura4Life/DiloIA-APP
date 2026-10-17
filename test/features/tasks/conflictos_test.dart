import 'package:diloia_app/core/constants.dart';
import 'package:diloia_app/data/database.dart';
import 'package:diloia_app/data/tasks_repository.dart';
import 'package:diloia_app/features/tasks/conflictos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fisica = Course(id: 1, nombre: 'Física I', color: 0, orden: 0);

  /// Lunes 12 de octubre de 2026 a la hora indicada.
  DateTime lunes(int hora, [int minuto = 0]) =>
      DateTime(2026, 10, 12, hora, minuto);

  var siguienteId = 1;

  /// Una tarea guardada de [tipo] que empieza a [inicio].
  TareaConCurso tarea(
    TipoActividad tipo,
    DateTime inicio, {
    Duration? duracion,
    bool completada = false,
  }) => (
    tarea: Task(
      id: siguienteId++,
      courseId: fisica.id,
      tipo: tipo,
      inicio: inicio,
      duracionMinutos: (duracion ?? tipo.duracionPorDefecto).inMinutes,
      completada: completada,
    ),
    curso: fisica,
  );

  /// El horario de una tarea nueva que se quiere guardar.
  Horario nueva(TipoActividad tipo, DateTime inicio, {Duration? duracion}) => (
    inicio: inicio,
    duracion: duracion ?? tipo.duracionPorDefecto,
    tipo: tipo,
  );

  group('evento con evento', () {
    test('chocan si se cruzan en parte', () {
      // Examen de 4 a 6 y exposición de 5 a 6.
      final examen = tarea(TipoActividad.examen, lunes(16));
      expect(
        detectarConflictos(nueva(TipoActividad.exposicion, lunes(17)), [
          examen,
        ]),
        [examen],
      );
    });

    test('chocan si uno está dentro del otro', () {
      // Examen de 3 horas (8 a 11) y una reunión de 9 a 10.
      final examen = tarea(
        TipoActividad.examen,
        lunes(8),
        duracion: const Duration(hours: 3),
      );
      expect(
        detectarConflictos(nueva(TipoActividad.otro, lunes(9)), [examen]),
        [examen],
      );
    });

    test('chocan si empiezan a la misma hora', () {
      final expo = tarea(TipoActividad.exposicion, lunes(10));
      expect(
        detectarConflictos(nueva(TipoActividad.examen, lunes(10)), [expo]),
        [expo],
      );
    });

    test('no chocan si uno termina justo cuando empieza el otro', () {
      // Exposición de 10 a 11 y examen de 11 a 1.
      final expo = tarea(TipoActividad.exposicion, lunes(10));
      expect(
        detectarConflictos(nueva(TipoActividad.examen, lunes(11)), [expo]),
        isEmpty,
      );
    });

    test('usa la duración que eligió el usuario', () {
      // Un examen de solo 1 hora (4 a 5) ya no choca con algo a las 5:30.
      final examenCorto = tarea(
        TipoActividad.examen,
        lunes(16),
        duracion: const Duration(hours: 1),
      );
      expect(
        detectarConflictos(nueva(TipoActividad.otro, lunes(17, 30)), [
          examenCorto,
        ]),
        isEmpty,
      );
    });

    test('no chocan en días distintos', () {
      final examen = tarea(TipoActividad.examen, lunes(16));
      expect(
        detectarConflictos(
          nueva(TipoActividad.examen, DateTime(2026, 10, 13, 16)),
          [examen],
        ),
        isEmpty,
      );
    });
  });

  test('una reunión es un evento: choca con un examen', () {
    final examen = tarea(TipoActividad.examen, lunes(16)); // 4 a 6
    expect(
      detectarConflictos(nueva(TipoActividad.reunion, lunes(17)), [examen]),
      [examen],
    );
  });

  group('las entregas nunca chocan', () {
    test('una entrega que vence durante un examen no avisa', () {
      final examen = tarea(TipoActividad.examen, lunes(16)); // 4 a 6
      expect(
        detectarConflictos(nueva(TipoActividad.entrega, lunes(16, 30)), [
          examen,
        ]),
        isEmpty,
      );
    });

    test('un examen nuevo no avisa por una entrega en su horario', () {
      final entrega = tarea(TipoActividad.entrega, lunes(9));
      expect(
        detectarConflictos(nueva(TipoActividad.examen, lunes(8)), [entrega]),
        isEmpty,
      );
    });

    test('dos entregas a la misma hora no chocan', () {
      final entrega = tarea(TipoActividad.entrega, lunes(23, 59));
      expect(
        detectarConflictos(nueva(TipoActividad.entrega, lunes(23, 59)), [
          entrega,
        ]),
        isEmpty,
      );
    });

    test('ni siquiera una entrega vieja que tenía 1 hora guardada', () {
      final entregaVieja = tarea(
        TipoActividad.entrega,
        lunes(16),
        duracion: const Duration(hours: 1),
      );
      expect(
        detectarConflictos(nueva(TipoActividad.reunion, lunes(16, 30)), [
          entregaVieja,
        ]),
        isEmpty,
      );
    });
  });

  group('qué tareas se comparan', () {
    test('las completadas no cuentan', () {
      final rendido = tarea(TipoActividad.examen, lunes(16), completada: true);
      expect(
        detectarConflictos(nueva(TipoActividad.examen, lunes(16)), [rendido]),
        isEmpty,
      );
    });

    test('una tarea no choca consigo misma al editarla', () {
      final examen = tarea(TipoActividad.examen, lunes(16));
      expect(
        detectarConflictos(nueva(TipoActividad.examen, lunes(17)), [
          examen,
        ], ignorarId: examen.tarea.id),
        isEmpty,
      );
    });

    test('devuelve todos los eventos que chocan, en orden', () {
      final examen = tarea(TipoActividad.examen, lunes(8)); // 8 a 10
      final expo = tarea(TipoActividad.exposicion, lunes(9)); // 9 a 10
      final otraHora = tarea(TipoActividad.otro, lunes(15));
      final entrega = tarea(TipoActividad.entrega, lunes(9, 30));
      final reunion = tarea(TipoActividad.reunion, lunes(10, 30));

      // Un examen de 3 horas, de 8 a 11.
      final choques = detectarConflictos(
        nueva(
          TipoActividad.examen,
          lunes(8),
          duracion: const Duration(hours: 3),
        ),
        [examen, expo, otraHora, entrega, reunion],
      );

      expect(choques, [examen, expo, reunion]);
    });
  });
}
