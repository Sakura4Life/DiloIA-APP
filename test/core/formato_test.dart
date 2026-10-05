import 'package:diloia_app/core/formato.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
    Intl.defaultLocale = 'es';
  });

  group('etiquetaDia', () {
    final hoy = DateTime(2026, 10, 4, 15, 30);

    test('usa Hoy, Mañana y Ayer sin importar la hora', () {
      expect(etiquetaDia(DateTime(2026, 10, 4, 23, 59), hoy: hoy), 'Hoy');
      expect(etiquetaDia(DateTime(2026, 10, 5, 0, 1), hoy: hoy), 'Mañana');
      expect(etiquetaDia(DateTime(2026, 10, 3, 8), hoy: hoy), 'Ayer');
    });

    test('el resto de días muestra la fecha en español', () {
      expect(
        etiquetaDia(DateTime(2026, 10, 6), hoy: hoy),
        'Martes 6 de octubre',
      );
    });

    test('agrega el año solo si no es el actual', () {
      expect(
        etiquetaDia(DateTime(2027, 1, 4), hoy: hoy),
        'Lunes 4 de enero de 2027',
      );
    });
  });

  test('el peso se muestra sin decimales innecesarios y con coma', () {
    expect(textoPeso(20), '20%');
    expect(textoPeso(12.5), '12,5%');
    expect(numeroPeso(10.05), '10,05');
  });
}
