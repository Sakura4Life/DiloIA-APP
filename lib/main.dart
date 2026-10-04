import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carga los nombres de días y meses en español para formatear fechas.
  await initializeDateFormatting('es');
  Intl.defaultLocale = 'es';

  // ProviderScope es donde Riverpod guarda el estado compartido de la app.
  runApp(const ProviderScope(child: DiloIAApp()));
}
