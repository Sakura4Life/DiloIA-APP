import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // La app se dibuja de borde a borde, también detrás de la barra de
  // navegación del teléfono. Android 15+ ya lo hace siempre; con esto los
  // teléfonos más viejos se ven igual.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Carga los nombres de días y meses en español para formatear fechas.
  await initializeDateFormatting('es');
  Intl.defaultLocale = 'es';

  // ProviderScope es donde Riverpod guarda el estado compartido de la app.
  runApp(const ProviderScope(child: DiloIAApp()));
}
