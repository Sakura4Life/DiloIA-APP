import 'package:diloia_app/core/widgets/boton_modo_tema.dart';
import 'package:diloia_app/data/providers.dart';
import 'package:diloia_app/data/tema_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio que arranca con el modo precargado, para probar que la app
/// recuerda la elección de una sesión anterior.
class _ConModoGuardado implements TemaRepository {
  _ConModoGuardado(this.modoGuardado);

  @override
  final ThemeMode? modoGuardado;

  @override
  Future<void> guardarModo(ThemeMode modo) async {}
}

/// Réplica mínima de la app de verdad: MaterialApp cuyo modo sale del
/// provider, con el botón adentro.
class _AppDePrueba extends ConsumerWidget {
  const _AppDePrueba();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: ThemeData(brightness: Brightness.light),
    darkTheme: ThemeData(brightness: Brightness.dark),
    themeMode: ref.watch(modoTemaProvider),
    home: const Scaffold(body: BotonModoTema()),
  );
}

void main() {
  /// Monta la app de prueba y devuelve el repositorio en memoria que usa,
  /// para revisar qué quedó guardado. [repositorio] permite simular una
  /// elección hecha en una sesión anterior.
  Future<TemaRepositoryEnMemoria> montar(
    WidgetTester tester, {
    TemaRepository? repositorio,
  }) async {
    final enMemoria = TemaRepositoryEnMemoria();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          temaRepositoryProvider.overrideWithValue(repositorio ?? enMemoria),
        ],
        child: const _AppDePrueba(),
      ),
    );
    await tester.pumpAndSettle();
    return enMemoria;
  }

  /// Modo que MaterialApp está usando para dibujar la app.
  ThemeMode? modoDe(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;

  testWidgets('de día muestra la luna, para pasar a la noche', (tester) async {
    await montar(tester);

    expect(modoDe(tester), ThemeMode.system);
    expect(find.byIcon(Icons.nights_stay_outlined), findsOneWidget);
    expect(find.byTooltip('Cambiar a modo oscuro'), findsOneWidget);
  });

  testWidgets('tocarlo pasa a modo oscuro', (tester) async {
    final repositorio = await montar(tester);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(modoDe(tester), ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
    // Queda escrito para la próxima vez que abra la app.
    expect(repositorio.modoGuardado, ThemeMode.dark);
  });

  testWidgets('tocarlo de nuevo vuelve a modo claro', (tester) async {
    final repositorio = await montar(tester);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(modoDe(tester), ThemeMode.light);
    expect(find.byIcon(Icons.nights_stay_outlined), findsOneWidget);
    expect(repositorio.modoGuardado, ThemeMode.light);
  });

  testWidgets('reabre en el modo que se había elegido', (tester) async {
    await montar(tester, repositorio: _ConModoGuardado(ThemeMode.dark));

    expect(modoDe(tester), ThemeMode.dark);
    expect(find.byIcon(Icons.light_mode), findsOneWidget);
    expect(find.byTooltip('Cambiar a modo claro'), findsOneWidget);
  });
}
