import 'package:diloia_app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
    Intl.defaultLocale = 'es';
  });

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DiloIAApp()));
    await tester.pumpAndSettle();
  }

  testWidgets('arranca en Pendientes con el botón de voz', (tester) async {
    await abrirApp(tester);

    expect(find.text('Sin pendientes'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });

  testWidgets('la barra inferior cambia de pestaña', (tester) async {
    await abrirApp(tester);

    await tester.tap(find.text('Calendario'));
    await tester.pumpAndSettle();
    expect(find.text('Tu mes de un vistazo'), findsOneWidget);

    await tester.tap(find.text('Panel'));
    await tester.pumpAndSettle();
    expect(find.text('Carga semanal'), findsOneWidget);
  });

  testWidgets('un toque corto explica que hay que mantener presionado', (
    tester,
  ) async {
    await abrirApp(tester);

    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    expect(find.text('Mantén presionado para dictar.'), findsOneWidget);
  });
}
