import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formato.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/tasks_repository.dart';
import '../voice/por_revisar_screen.dart';
import 'filtro_tareas.dart';
import 'task_form_screen.dart';

/// Pestaña "Pendientes": las tareas ordenadas por fecha y agrupadas por día.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  FiltroTareas _filtro = FiltroTareas.pendientes;

  /// Tareas que se acaban de marcar o desmarcar y ya no encajan en el filtro
  /// (por ejemplo, una tarea completada en "Pendientes"). Siguen en pantalla
  /// mientras dura su animación de salida; al terminar, se quitan de aquí y
  /// el filtro las oculta.
  final _saliendo = <int>{};

  /// Tareas que el usuario acaba de borrar deslizando. Se ocultan al instante,
  /// sin esperar a que la base de datos confirme el borrado: Flutter exige que
  /// una tarjeta deslizada desaparezca de la lista en ese mismo momento.
  final _borrandose = <int>{};

  Future<bool> _confirmarBorrado(TareaConCurso item) async {
    final nombre = item.tarea.titulo ?? item.tarea.tipo.etiqueta;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar esta tarea?'),
        content: Text('«$nombre» de ${item.curso.nombre} se borrará.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    return confirmado ?? false;
  }

  Future<void> _borrar(Task tarea) async {
    final repo = ref.read(tasksRepositoryProvider);
    setState(() => _borrandose.add(tarea.id));
    await repo.borrar(tarea.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Tarea borrada'),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () async {
              await repo.restaurar(tarea);
              if (mounted) setState(() => _borrandose.remove(tarea.id));
            },
          ),
        ),
      );
  }

  Future<void> _marcar(Task tarea, {required bool completada}) async {
    final repo = ref.read(tasksRepositoryProvider);
    // ¿Sigue encajando en el filtro después del cambio? En "Todas" sí (solo
    // se tacha); en "Pendientes", una tarea completada ya no.
    final sigue = _filtro.incluye(
      tarea.copyWith(completada: completada),
      ahora: DateTime.now(),
    );
    if (!sigue) setState(() => _saliendo.add(tarea.id));
    await repo.marcarCompletada(tarea.id, completada: completada);
    if (sigue || !mounted) return;

    // La tarea se va de la lista: por si fue un toque equivocado, se puede
    // deshacer, igual que al borrar.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            completada ? 'Tarea completada' : 'Tarea marcada como pendiente',
          ),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () =>
                repo.marcarCompletada(tarea.id, completada: !completada),
          ),
        ),
      );
  }

  void _cambiarFiltro() {
    setState(() {
      _filtro = _filtro.siguiente;
      _saliendo.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Ej.: "sábado, 3 de octubre". El idioma lo fija Intl.defaultLocale.
    final ahora = DateTime.now();
    final hoy = DateFormat("EEEE, d 'de' MMMM").format(ahora);
    final tareas = ref.watch(tareasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Hoy es $hoy',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // Cada toque pasa al siguiente filtro:
              // Pendientes → Completadas → Pasadas → Todas → Pendientes…
              ActionChip(
                avatar: Icon(_filtro.icono, size: 18),
                label: Text(_filtro.etiqueta),
                tooltip: 'Cambiar filtro',
                onPressed: _cambiarFiltro,
              ),
            ],
          ),
        ),
        // Dictados que esperan internet o confirmación (solo si hay alguno).
        const AvisoPorRevisar(),
        Expanded(
          child: tareas.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
            data: (todas) {
              final visibles = [
                for (final item in todas)
                  if (!_borrandose.contains(item.tarea.id) &&
                      (_filtro.incluye(item.tarea, ahora: ahora) ||
                          _saliendo.contains(item.tarea.id)))
                    item,
              ];
              if (visibles.isEmpty) {
                return EmptyState(
                  icono: Icons.task_alt,
                  titulo: _filtro.mensajeVacio,
                  mensaje: todas.isEmpty
                      ? 'Toca el micrófono y dicta tu primera tarea.\n'
                            'Por ejemplo: «examen de física a las 8, vale 30%».'
                      : 'Toca «${_filtro.etiqueta}» para ver otras tareas.',
                );
              }
              return _ListaAgrupada(
                tareas: visibles,
                saliendo: _saliendo,
                confirmarBorrado: _confirmarBorrado,
                onBorrar: _borrar,
                onMarcar: _marcar,
                onSalio: (id) => setState(() => _saliendo.remove(id)),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Lista con un título por día ("Hoy", "Mañana", "Lunes 6 de octubre") y las
/// tareas de ese día debajo. Las tareas ya llegan ordenadas por fecha.
class _ListaAgrupada extends StatelessWidget {
  const _ListaAgrupada({
    required this.tareas,
    required this.saliendo,
    required this.confirmarBorrado,
    required this.onBorrar,
    required this.onMarcar,
    required this.onSalio,
  });

  final List<TareaConCurso> tareas;

  /// Ids de las tareas que están haciendo su animación de salida.
  final Set<int> saliendo;
  final Future<bool> Function(TareaConCurso) confirmarBorrado;
  final void Function(Task) onBorrar;
  final void Function(Task, {required bool completada}) onMarcar;
  final ValueChanged<int> onSalio;

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final filas = <Widget>[];
    String? diaAnterior;

    for (final item in tareas) {
      final dia = etiquetaDia(item.tarea.inicio, hoy: ahora);
      if (dia != diaAnterior) {
        filas.add(_TituloDia(dia));
        diaAnterior = dia;
      }
      final id = item.tarea.id;
      filas.add(
        // La clave mantiene la animación pegada a su tarea aunque la lista
        // cambie mientras tanto.
        _Saliente(
          key: ValueKey('saliente-$id'),
          activo: saliendo.contains(id),
          onTerminado: () => onSalio(id),
          child: _FilaTarea(
            item: item,
            ahora: ahora,
            confirmarBorrado: () => confirmarBorrado(item),
            onBorrar: () => onBorrar(item.tarea),
            onMarcar: (valor) => onMarcar(item.tarea, completada: valor),
          ),
        ),
      );
    }

    // Espacio al final para que el botón de voz no tape la última tarea.
    return ListView(
      padding: const EdgeInsets.only(bottom: 104),
      children: filas,
    );
  }
}

/// Animación de una tarea que se va de la lista: primero se queda quieta un
/// instante (para que se vea el check y el tachado) y luego se desvanece y se
/// encoge, y las de abajo suben.
class _Saliente extends StatefulWidget {
  const _Saliente({
    super.key,
    required this.activo,
    required this.onTerminado,
    required this.child,
  });

  final bool activo;
  final VoidCallback onTerminado;
  final Widget child;

  @override
  State<_Saliente> createState() => _SalienteState();
}

class _SalienteState extends State<_Saliente>
    with SingleTickerProviderStateMixin {
  late final _controlador =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 650),
      )..addStatusListener((estado) {
        if (estado == AnimationStatus.completed) widget.onTerminado();
      });

  /// Va de 1 (se ve completa) a 0 (desapareció). El primer 45 % del tiempo
  /// no cambia: es la pausa para ver el check.
  late final _visible = ReverseAnimation(
    CurvedAnimation(
      parent: _controlador,
      curve: const Interval(0.45, 1, curve: Curves.easeInOut),
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.activo) _controlador.forward();
  }

  @override
  void didUpdateWidget(_Saliente anterior) {
    super.didUpdateWidget(anterior);
    if (widget.activo && !anterior.activo) _controlador.forward(from: 0);
    if (!widget.activo && anterior.activo) _controlador.reset();
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _visible,
      // Se encoge hacia arriba: las tareas de abajo suben a ocupar su lugar.
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _visible, child: widget.child),
    );
  }
}

class _TituloDia extends StatelessWidget {
  const _TituloDia(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// Una tarea: casilla para completarla, franja con el color del curso, toque
/// para editarla y deslizar hacia la izquierda para borrarla.
class _FilaTarea extends StatelessWidget {
  const _FilaTarea({
    required this.item,
    required this.ahora,
    required this.confirmarBorrado,
    required this.onBorrar,
    required this.onMarcar,
  });

  final TareaConCurso item;
  final DateTime ahora;
  final Future<bool> Function() confirmarBorrado;
  final VoidCallback onBorrar;
  final ValueChanged<bool> onMarcar;

  @override
  Widget build(BuildContext context) {
    final tarea = item.tarea;
    final curso = item.curso;
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final peso = tarea.pesoPorcentaje;
    final titulo = tarea.titulo;
    final vencida = !tarea.completada && yaPaso(tarea, ahora: ahora);

    // Un evento muestra de cuándo a cuándo ("4:00 p. m. – 6:00 p. m."); una
    // entrega, solo la hora límite.
    final cuando = tarea.tipo.esPlazo
        ? textoHora(tarea.inicio)
        : textoLapso(tarea.inicio, finDeTarea(tarea));

    // Arriba, en negrita: "Laboratorio 3 · Física" (o "Entrega · Física" si
    // no hay título), para reconocer el curso de un vistazo.
    // Abajo: "Entrega · 4:00 p. m. · 20% de la nota" (el tipo solo si hay
    // título, porque si no ya está arriba).
    final detalles = [
      if (titulo != null) tarea.tipo.etiqueta,
      cuando,
      if (peso != null) '${textoPeso(peso)} de la nota',
    ].join(' · ');

    return Dismissible(
      key: ValueKey(tarea.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: colores.error,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: colores.onError),
      ),
      // Pregunta antes de borrar; si el usuario cancela, la tarjeta vuelve.
      confirmDismiss: (_) => confirmarBorrado(),
      onDismissed: (_) => onBorrar(),
      child: Card.filled(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => TaskFormScreen(existente: tarea),
            ),
          ),
          // La franja de color es el borde izquierdo: crece junto con el
          // contenido, sea de una línea o de varias.
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(curso.color), width: 6),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            child: Row(
              children: [
                Checkbox(
                  value: tarea.completada,
                  onChanged: (valor) => onMarcar(valor ?? false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Un solo párrafo: si no cabe en una línea, baja a la
                      // segunda; si tampoco, se corta con "…" al final, que
                      // siempre cae en el nombre del curso.
                      Text(
                        '${titulo ?? tarea.tipo.etiqueta} · ${curso.nombre}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textos.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: tarea.completada
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (vencida)
                              TextSpan(
                                text: 'Vencida · ',
                                style: TextStyle(
                                  color: colores.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            TextSpan(text: detalles),
                          ],
                        ),
                        style: textos.bodyMedium?.copyWith(
                          color: colores.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
