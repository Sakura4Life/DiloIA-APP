import 'package:diloia_app/core/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('los eventos tienen duración: examen 2 horas, los demás 1 hora', () {
    expect(TipoActividad.examen.duracionPorDefecto, const Duration(hours: 2));
    expect(
      TipoActividad.exposicion.duracionPorDefecto,
      const Duration(hours: 1),
    );
    expect(TipoActividad.reunion.duracionPorDefecto, const Duration(hours: 1));
    expect(TipoActividad.otro.duracionPorDefecto, const Duration(hours: 1));
  });

  test('solo la entrega es un plazo, sin duración', () {
    expect(TipoActividad.entrega.esPlazo, isTrue);
    expect(TipoActividad.entrega.duracionPorDefecto, Duration.zero);
    for (final tipo in TipoActividad.values) {
      if (tipo == TipoActividad.entrega) continue;
      expect(tipo.esPlazo, isFalse, reason: tipo.name);
    }
  });

  test('los tipos del JSON de la IA se convierten al enum', () {
    const tiposDelContrato = [
      'entrega',
      'examen',
      'exposicion',
      'reunion',
      'otro',
    ];
    expect(TipoActividad.values.map((t) => t.name), tiposDelContrato);
  });
}
