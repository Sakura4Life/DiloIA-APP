import 'package:diloia_app/core/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el examen dura 2 horas y los demás tipos 1 hora', () {
    expect(TipoActividad.examen.duracionPorDefecto, const Duration(hours: 2));
    for (final tipo in TipoActividad.values) {
      if (tipo == TipoActividad.examen) continue;
      expect(tipo.duracionPorDefecto, const Duration(hours: 1));
    }
  });

  test('los tipos del JSON de la IA se convierten al enum', () {
    const tiposDelContrato = [
      'entrega',
      'examen',
      'proyecto',
      'exposicion',
      'otro',
    ];
    for (final tipo in tiposDelContrato) {
      expect(TipoActividad.values.byName(tipo).name, tipo);
    }
  });
}
