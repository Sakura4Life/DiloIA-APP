import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/providers.dart';
import 'data/tema_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // La app se dibuja de borde a borde, también detrás de la barra de
  // navegación del teléfono. Android 15+ ya lo hace siempre; con esto los
  // teléfonos más viejos se ven igual.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Carga los nombres de días y meses en español para formatear fechas.
  await initializeDateFormatting('es');
  Intl.defaultLocale = 'es';

  // Preferencia de modo claro u oscuro guardada en una sesión anterior.
  final preferencias = await SharedPreferences.getInstance();

  // ProviderScope es donde Riverpod guarda el estado compartido de la app.
  runApp(
    ProviderScope(
      overrides: [
        temaRepositoryProvider.overrideWithValue(
          TemaRepositoryPreferencias(preferencias),
        ),
      ],
      child: const DiloIAApp(),
    ),
  );
}
