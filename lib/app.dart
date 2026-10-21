import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/widgets/boton_modo_tema.dart';
import 'data/providers.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/courses/courses_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/tasks/task_form_screen.dart';
import 'features/tasks/tasks_screen.dart';
import 'features/voice/cola_automatica.dart';
import 'features/voice/voice_button.dart';

/// Raíz visual de la app: tema, idioma y pantalla inicial.
class DiloIAApp extends ConsumerWidget {
  const DiloIAApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'DiloIA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro,
      darkTheme: AppTheme.oscuro,
      // Modo elegido por el usuario; si nunca eligió, sigue al del sistema.
      themeMode: ref.watch(modoTemaProvider),
      // Textos del sistema (calendarios, selectores de fecha y hora) en español.
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => _BarraDelSistema(child: child!),
      // ColaAutomatica envía a la IA los dictados guardados sin internet
      // apenas vuelve la conexión.
      home: const ColaAutomatica(child: HomeShell()),
    );
  }
}

/// Ajusta la barra de navegación del teléfono (los botones de atrás, inicio y
/// recientes) al modo claro u oscuro de la app.
///
/// La barra se deja transparente para que detrás se vea la propia app, y sus
/// íconos se pintan oscuros en modo claro y claros en modo oscuro. Sin esto,
/// Android puede poner un fondo claro en modo oscuro, o dejar los íconos
/// del mismo color que el fondo en modo claro.
class _BarraDelSistema extends StatelessWidget {
  const _BarraDelSistema({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: oscuro
            ? Brightness.light
            : Brightness.dark,
        // Quita el velo semitransparente que Android agrega encima de los
        // botones, que era el que se veía claro en modo oscuro.
        systemNavigationBarContrastEnforced: false,
      ),
      child: child,
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

  void _abrir(Widget pantalla) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => pantalla));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_indice]),
        actions: [
          IconButton(
            tooltip: 'Cursos',
            icon: const Icon(Icons.school_outlined),
            onPressed: () => _abrir(const CoursesScreen()),
          ),
          IconButton(
            tooltip: 'Nueva tarea',
            icon: const Icon(Icons.add),
            onPressed: () => _abrir(const TaskFormScreen()),
          ),
          // Al final, como los demás: mismo tamaño y sin márgenes extra.
          const BotonModoTema(),
        ],
      ),
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
