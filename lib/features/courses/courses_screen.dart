import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/empty_state.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'course_dialog.dart';

/// Pantalla para crear, editar y borrar cursos.
class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key});

  Future<void> _crear(
    BuildContext context,
    WidgetRef ref,
    List<Course> cursos,
  ) async {
    final datos = await mostrarDialogoCurso(
      context,
      nombresExistentes: [for (final c in cursos) c.nombre],
    );
    if (datos == null) return;
    await ref
        .read(coursesRepositoryProvider)
        .crear(nombre: datos.nombre, color: datos.color);
  }

  Future<void> _editar(
    BuildContext context,
    WidgetRef ref,
    Course curso,
    List<Course> cursos,
  ) async {
    final datos = await mostrarDialogoCurso(
      context,
      nombresExistentes: [for (final c in cursos) c.nombre],
      nombreInicial: curso.nombre,
      colorInicial: curso.color,
    );
    if (datos == null) return;
    await ref
        .read(coursesRepositoryProvider)
        .actualizar(curso.copyWith(nombre: datos.nombre, color: datos.color));
  }

  Future<void> _borrar(
    BuildContext context,
    WidgetRef ref,
    Course curso,
  ) async {
    final repo = ref.read(coursesRepositoryProvider);
    final cantidad = await repo.contarTareas(curso.id);
    if (!context.mounted) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar «${curso.nombre}»?'),
        content: Text(
          cantidad == 0
              ? 'El curso no tiene tareas.'
              : 'También se borrarán sus $cantidad '
                    '${cantidad == 1 ? 'tarea' : 'tareas'}. '
                    'No se puede deshacer.',
        ),
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
    if (confirmado == true) await repo.borrar(curso.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursos = ref.watch(cursosProvider);
    final lista = cursos.value ?? const <Course>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Cursos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _crear(context, ref, lista),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo curso'),
      ),
      body: cursos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (cursos) {
          if (cursos.isEmpty) {
            return const EmptyState(
              icono: Icons.school_outlined,
              titulo: 'Aún no tienes cursos',
              mensaje:
                  'Agrega los cursos que llevas este ciclo para '
                  'organizar tus tareas por color.',
            );
          }
          return _ListaReordenable(
            cursos: cursos,
            onEditar: (curso) => _editar(context, ref, curso, cursos),
            onBorrar: (curso) => _borrar(context, ref, curso),
          );
        },
      ),
    );
  }
}

/// Lista de cursos que se reordena arrastrando el ícono ≡ de cada fila. El
/// orden elegido es el mismo que se usa al elegir un curso en una tarea.
class _ListaReordenable extends ConsumerStatefulWidget {
  const _ListaReordenable({
    required this.cursos,
    required this.onEditar,
    required this.onBorrar,
  });

  final List<Course> cursos;
  final ValueChanged<Course> onEditar;
  final ValueChanged<Course> onBorrar;

  @override
  ConsumerState<_ListaReordenable> createState() => _ListaReordenableState();
}

class _ListaReordenableState extends ConsumerState<_ListaReordenable> {
  /// Copia local del orden mientras se guarda en la base. Sin ella, al soltar
  /// un curso volvería un instante a su lugar viejo antes de saltar al nuevo.
  List<Course>? _ordenLocal;

  Future<void> _mover(int desde, int hasta) async {
    final lista = [...(_ordenLocal ?? widget.cursos)];
    final curso = lista.removeAt(desde);
    lista.insert(hasta, curso);
    setState(() => _ordenLocal = lista);

    await ref.read(coursesRepositoryProvider).reordenar([
      for (final c in lista) c.id,
    ]);
    if (mounted) setState(() => _ordenLocal = null);
  }

  @override
  Widget build(BuildContext context) {
    final cursos = _ordenLocal ?? widget.cursos;
    final colores = Theme.of(context).colorScheme;

    return ReorderableListView.builder(
      // Las asas de arrastre se ponen a mano (ícono ≡) para que se vean.
      buildDefaultDragHandles: false,
      header: cursos.length < 2
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Arrastra ≡ para cambiar el orden.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colores.onSurfaceVariant),
              ),
            ),
      // Espacio al final para que el botón flotante no tape el último.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: cursos.length,
      // Con onReorderItem, `hasta` ya viene corregido (versión nueva de la API).
      onReorderItem: _mover,
      itemBuilder: (context, i) {
        final curso = cursos[i];
        return ListTile(
          key: ValueKey(curso.id),
          leading: CircleAvatar(backgroundColor: Color(curso.color)),
          title: Text(curso.nombre),
          onTap: () => widget.onEditar(curso),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Borrar curso',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => widget.onBorrar(curso),
              ),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
