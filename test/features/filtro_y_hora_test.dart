import 'package:diloia_app/core/constants.dart';
import 'package:diloia_app/core/formato.dart';
import 'package:diloia_app/data/database.dart';
import 'package:diloia_app/features/tasks/filtro_tareas.dart';
import 'package:diloia_app/features/tasks/selector_hora.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FiltroTareas', () {
    final ahora = DateTime(2026, 10, 4, 10);

    Task tarea({required bool completada, required DateTime inicio}) => Task(
      id: 1,
      courseId: 1,
      tipo: TipoActividad.entrega,
      inicio: inicio,
      duracionMinutos: 60,
      completada: completada,
    );

    final futuraPendiente = tarea(
      completada: false,
      inicio: DateTime(2026, 10, 9),
    );
    final futuraHecha = tarea(completada: true, inicio: DateTime(2026, 10, 9));
    final vencida = tarea(completada: false, inicio: DateTime(2026, 10, 1));
    final pasadaHecha = tarea(completada: true, inicio: DateTime(2026, 10, 1));
    final todas = [futuraPendiente, futuraHecha, vencida, pasadaHecha];

    List<Task> con(FiltroTareas filtro) =>
        todas.where((t) => filtro.incluye(t, ahora: ahora)).toList();

    test('empieza en Pendientes, recorre los cuatro y vuelve a empezar', () {
      var filtro = FiltroTareas.values.first;
      final recorrido = <String>[];
      for (var i = 0; i < 5; i++) {
        recorrido.add(filtro.etiqueta);
        filtro = filtro.siguiente;
      }
      expect(recorrido, [
        'Pendientes',
        'Completadas',
        'Pasadas',
        'Todas',
        'Pendientes',
      ]);
    });

    test('cada filtro muestra lo que corresponde', () {
      expect(con(FiltroTareas.todas), todas);
      // Las vencidas sin marcar ya no salen en Pendientes.
      expect(con(FiltroTareas.pendientes), [futuraPendiente]);
      expect(con(FiltroTareas.completadas), [futuraHecha, pasadaHecha]);
      expect(con(FiltroTareas.pasadas), [vencida, pasadaHecha]);
    });

    test('un evento en curso sigue pendiente hasta que termina', () {
      // Examen de 9 a 11; son las 10.
      final examen = Task(
        id: 2,
        courseId: 1,
        tipo: TipoActividad.examen,
        inicio: DateTime(2026, 10, 4, 9),
        duracionMinutos: 120,
        completada: false,
      );
      expect(FiltroTareas.pendientes.incluye(examen, ahora: ahora), isTrue);
      expect(FiltroTareas.pasadas.incluye(examen, ahora: ahora), isFalse);

      final alTerminar = DateTime(2026, 10, 4, 11);
      expect(
        FiltroTareas.pendientes.incluye(examen, ahora: alTerminar),
        isFalse,
      );
      expect(FiltroTareas.pasadas.incluye(examen, ahora: alTerminar), isTrue);
    });

    test('una entrega pasa al llegar su hora límite', () {
      final entrega = tarea(
        completada: false,
        inicio: DateTime(2026, 10, 4, 10),
      );
      expect(FiltroTareas.pasadas.incluye(entrega, ahora: ahora), isTrue);
    });
  });

  group('reloj de 12 horas', () {
    test('convierte a 24 horas, incluidas las 12 a. m. y 12 p. m.', () {
      expect(
        horaDesde12(hora12: 12, minuto: 0, pm: false),
        const TimeOfDay(hour: 0, minute: 0),
      );
      expect(
        horaDesde12(hora12: 12, minuto: 30, pm: true),
        const TimeOfDay(hour: 12, minute: 30),
      );
      expect(
        horaDesde12(hora12: 4, minuto: 5, pm: true),
        const TimeOfDay(hour: 16, minute: 5),
      );
    });

    test('y de vuelta a 12 horas', () {
      expect(hora12De(const TimeOfDay(hour: 0, minute: 0)), 12);
      expect(hora12De(const TimeOfDay(hour: 12, minute: 0)), 12);
      expect(hora12De(const TimeOfDay(hour: 16, minute: 0)), 4);
    });
  });

  group('textoFaltante', () {
    final ahora = DateTime(2026, 10, 4, 10, 0);

    test('días y horas', () {
      expect(
        textoFaltante(DateTime(2026, 10, 6, 13, 0), ahora: ahora),
        'Faltan 2 días y 3 horas',
      );
      expect(
        textoFaltante(DateTime(2026, 10, 5, 10, 0), ahora: ahora),
        'Falta 1 día',
      );
    });

    test('horas y minutos, en singular cuando toca', () {
      expect(
        textoFaltante(DateTime(2026, 10, 4, 11, 5), ahora: ahora),
        'Falta 1 hora y 5 minutos',
      );
      expect(
        textoFaltante(DateTime(2026, 10, 4, 10, 1), ahora: ahora),
        'Falta 1 minuto',
      );
    });

    test('devuelve null si ya pasó', () {
      expect(textoFaltante(DateTime(2026, 10, 4, 9, 0), ahora: ahora), isNull);
      expect(textoFaltante(ahora, ahora: ahora), isNull);
    });
  });
}
