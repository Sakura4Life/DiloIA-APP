import 'package:diloia_app/core/constants.dart';
import 'package:diloia_app/core/fecha_lima.dart';
import 'package:diloia_app/data/database.dart';
import 'package:diloia_app/features/voice/borrador_desde_ia.dart';
import 'package:diloia_app/features/voice/extraccion_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ahora = DateTime(2026, 10, 6, 10, 0); // martes
  const fisica = Course(id: 1, nombre: 'Física I', color: 0, orden: 0);
  const calculo = Course(id: 2, nombre: 'Cálculo II', color: 0, orden: 1);
  const cursos = [fisica, calculo];

  BorradorDeVoz convertir(Map<String, dynamic> json) => borradorDesdeIA(
    ResultadoIA.desdeJson({'transcripcion': 'algo', 'tipo': 'otro', ...json}),
    cursos: cursos,
    ahora: ahora,
  );

  test('llena todos los campos con lo que entendió la IA', () {
    final r = convertir({
      'materia': 'Física I',
      'tipo': 'entrega',
      'titulo': 'Laboratorio 3',
      'fecha': '2026-10-09',
      'hora': '16:30',
      'peso': 20,
    });

    expect(r.borrador.courseId, fisica.id);
    expect(r.borrador.tipo, TipoActividad.entrega);
    expect(r.borrador.titulo, 'Laboratorio 3');
    expect(r.borrador.fecha, DateTime(2026, 10, 9));
    expect(r.borrador.hora, const TimeOfDay(hour: 16, minute: 30));
    expect(r.borrador.peso, 20);
    expect(r.materiaNueva, isNull);
  });

  test('reconoce el curso aunque cambien tildes y mayúsculas', () {
    expect(convertir({'materia': 'calculo ii'}).borrador.courseId, calculo.id);
  });

  test('un curso que no existe se ofrece para crearlo', () {
    final r = convertir({'materia': 'Historia'});
    expect(r.borrador.courseId, isNull);
    expect(r.materiaNueva, 'Historia');
  });

  test('si no se dijo curso, no ofrece crear ninguno', () {
    final r = convertir({});
    expect(r.borrador.courseId, isNull);
    expect(r.materiaNueva, isNull);
  });

  test('lo que no se dijo queda vacío para que el usuario lo llene', () {
    final r = convertir({'tipo': 'examen'});
    expect(r.borrador.fecha, isNull);
    expect(r.borrador.hora, isNull);
    expect(r.borrador.peso, isNull);
    expect(r.borrador.titulo, isNull);
    expect(r.borrador.faltantes, ['curso', 'fecha', 'hora']);
  });

  test('una fecha que ya pasó se deja vacía', () {
    // Por ejemplo, un dictado que esperó días sin internet.
    expect(convertir({'fecha': '2026-10-05'}).borrador.fecha, isNull);
    // Hoy sí vale.
    expect(convertir({'fecha': '2026-10-06'}).borrador.fecha, isNotNull);
  });

  test('datos con formato raro no rompen la tarjeta', () {
    final r = convertir({
      'tipo': 'reunion', // no es un tipo válido
      'fecha': 'viernes',
      'hora': '25:00',
      'peso': 150,
    });
    expect(r.borrador.tipo, TipoActividad.otro);
    expect(r.borrador.fecha, isNull);
    expect(r.borrador.hora, isNull);
    expect(r.borrador.peso, isNull);
  });

  group('fechaEnLima', () {
    test('usa la fecha de Lima aunque el celular tenga otra zona', () {
      // 3:00 a. m. en UTC del día 7 son las 10:00 p. m. del día 6 en Lima.
      expect(fechaEnLima(DateTime.utc(2026, 10, 7, 3)), '2026-10-06');
      expect(fechaEnLima(DateTime.utc(2026, 10, 7, 5)), '2026-10-07');
    });
  });
}
