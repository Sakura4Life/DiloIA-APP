import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/voice/voice_button.dart';

/// Raíz visual de la app: tema, idioma y pantalla inicial.
class DiloIAApp extends StatelessWidget {
  const DiloIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiloIA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro,
      darkTheme: AppTheme.oscuro,
      // Textos del sistema (calendarios, selectores de fecha y hora) en español.
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeShell(),
    );
  }
}

/// Estructura principal: barra superior, las tres pestañas y el botón de voz,
/// que está siempre visible porque dictar es la acción central de la app.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _indice = 0;

  static const _titulos = ['Pendientes', 'Calendario', 'Panel'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titulos[_indice])),
      // IndexedStack mantiene vivas las tres pantallas: al volver a una
      // pestaña conserva su estado (por ejemplo, la posición del scroll).
      body: IndexedStack(
        index: _indice,
        children: const [TasksScreen(), CalendarScreen(), DashboardScreen()],
      ),
      floatingActionButton: const VoiceButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Pendientes',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Panel',
          ),
        ],
      ),
    );
  }
}
