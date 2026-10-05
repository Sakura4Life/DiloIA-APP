import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/formato.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../courses/course_dialog.dart';
import 'selector_hora.dart';
import 'task_draft.dart';

/// Formulario para crear o editar una tarea.
///
/// - Sin parámetros: tarea nueva, todo vacío.
/// - Con [existente]: edita esa tarea.
/// - Con [borrador]: tarea nueva con datos ya llenados (lo usará la fase 4
///   para mostrar lo que entendió la IA).
class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.existente, this.borrador});

  final Task? existente;
  final BorradorTarea? borrador;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

/// Foto de todo lo que hay en el formulario, para saber si el usuario cambió
/// algo. Es un *record*: dos fotos con los mismos valores son iguales.
typedef _Contenido = ({
  int? curso,
  TipoActividad? tipo,
  String titulo,
  DateTime? fecha,
  TimeOfDay? hora,
  String peso,
});

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  late final BorradorTarea _borrador;
  late final TextEditingController _peso;
  late final TextEditingController _titulo;
  late final _Contenido _contenidoInicial;
  final _formKey = GlobalKey<FormState>();

  /// Se activa al pulsar "Guardar" con campos vacíos, para marcarlos en rojo.
  bool _mostrarFaltantes = false;
  bool _horaYaPaso = false;
  bool _guardando = false;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final existente = widget.existente;
    _borrador = existente != null
        ? BorradorTarea.desdeTarea(existente)
        : (widget.borrador ?? BorradorTarea());
    final peso = _borrador.peso;
    _peso = TextEditingController(text: peso == null ? '' : numeroPeso(peso));
    _titulo = TextEditingController(text: _borrador.titulo ?? '');
    _contenidoInicial = _contenido();
  }

  @override
  void dispose() {
    _peso.dispose();
    _titulo.dispose();
    super.dispose();
  }

  _Contenido _contenido() {
    final fecha = _borrador.fecha;
    return (
      curso: _borrador.courseId,
      tipo: _borrador.tipo,
      titulo: _titulo.text.trim(),
      // Solo el día: la hora se compara aparte.
      fecha: fecha == null
          ? null
          : DateTime(fecha.year, fecha.month, fecha.day),
      hora: _borrador.hora,
      peso: _peso.text.trim(),
    );
  }

  /// Si salir ahora perdería algo. Al crear: si hay cualquier dato. Al editar:
  /// si algo cambió respecto a la tarea guardada.
  bool get _hayCambios {
    const vacio = (
      curso: null,
      tipo: null,
      titulo: '',
      fecha: null,
      hora: null,
      peso: '',
    );
    final actual = _contenido();
    return _editando ? actual != _contenidoInicial : actual != vacio;
  }

  /// Se llama al pulsar la flecha de arriba o el botón "atrás" del teléfono
  /// cuando hay datos sin guardar.
  Future<void> _confirmarSalida() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar los cambios?'),
        content: Text(
          _editando
              ? 'Los cambios que hiciste en esta tarea se perderán.'
              : 'Lo que llenaste en esta tarea se perderá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    // Navigator.pop siempre sale, aunque PopScope esté bloqueando el "atrás".
    if (salir == true && mounted) Navigator.pop(context);
  }

  Future<void> _elegirCurso(List<Course> cursos) async {
    final elegido = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      // Necesario para que la hoja pueda crecer al deslizarla hacia arriba.
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 8,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Elige un curso',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final curso in cursos)
              ListTile(
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: Color(curso.color),
                ),
                title: Text(curso.nombre),
                trailing: curso.id == _borrador.courseId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, curso.id),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Nuevo curso'),
              // -1 significa "crear uno nuevo".
              onTap: () => Navigator.pop(context, -1),
            ),
          ],
        ),
      ),
    );
    if (elegido == null || !mounted) return;
    if (elegido == -1) {
      await _crearCurso(cursos);
    } else {
      setState(() => _borrador.courseId = elegido);
    }
  }

  Future<void> _crearCurso(List<Course> cursos) async {
    final datos = await mostrarDialogoCurso(
      context,
      nombresExistentes: [for (final c in cursos) c.nombre],
    );
    if (datos == null) return;
    final id = await ref
        .read(coursesRepositoryProvider)
        .crear(nombre: datos.nombre, color: datos.color);
    if (mounted) setState(() => _borrador.courseId = id);
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final actual = _borrador.fecha;
    final fecha = await showDatePicker(
      context: context,
      // Una tarea vencida que se edita abre el calendario en hoy, porque los
      // días pasados no se pueden elegir.
      initialDate: actual == null || actual.isBefore(hoy) ? hoy : actual,
      firstDate: hoy,
      lastDate: DateTime(ahora.year + 2, 12, 31),
    );
    if (fecha != null) {
      setState(() {
        _borrador.fecha = fecha;
        _horaYaPaso = false;
      });
    }
  }

  /// Ruedas para elegir la hora, como al programar una alarma (ver
  /// selector_hora.dart).
  Future<void> _elegirHora() async {
    final elegida = await mostrarSelectorHora(
      context,
      inicial: _borrador.hora ?? const TimeOfDay(hour: 8, minute: 0),
      fecha: _borrador.fecha,
    );
    if (elegida != null) {
      setState(() {
        _borrador.hora = elegida;
        _horaYaPaso = false;
      });
    }
  }

  Future<void> _guardar() async {
    final pesoValido = _formKey.currentState!.validate();
    final yaPaso = _borrador.yaPaso(
      ahora: DateTime.now(),
      inicioOriginal: widget.existente?.inicio,
    );
    if (!_borrador.estaCompleto || !pesoValido || yaPaso) {
      setState(() {
        _mostrarFaltantes = true;
        _horaYaPaso = yaPaso;
      });
      return;
    }

    setState(() => _guardando = true);
    final repo = ref.read(tasksRepositoryProvider);
    final tipo = _borrador.tipo!;
    final inicio = _borrador.inicio!;
    final peso = leerPeso(_peso.text);
    final textoTitulo = _titulo.text.trim();
    final titulo = textoTitulo.isEmpty ? null : textoTitulo;
    final existente = widget.existente;

    if (existente != null) {
      await repo.actualizar(
        existente.copyWith(
          courseId: _borrador.courseId,
          tipo: tipo,
          titulo: Value(titulo),
          inicio: inicio,
          duracionMinutos: tipo.duracionPorDefecto.inMinutes,
          pesoPorcentaje: Value(peso),
        ),
      );
    } else {
      await repo.crear(
        TasksCompanion.insert(
          courseId: _borrador.courseId!,
          tipo: tipo,
          titulo: Value(titulo),
          inicio: inicio,
          duracionMinutos: tipo.duracionPorDefecto.inMinutes,
          pesoPorcentaje: Value(peso),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cursos = ref.watch(cursosProvider).value ?? const <Course>[];
    final curso = cursos.where((c) => c.id == _borrador.courseId).firstOrNull;
    final faltan = _mostrarFaltantes ? _borrador.faltantes : const <String>[];
    final fecha = _borrador.fecha;
    final hora = _borrador.hora;

    // PopScope intercepta la flecha de arriba y el botón "atrás" del teléfono:
    // si hay datos sin guardar, pregunta antes de salir.
    return PopScope<void>(
      canPop: !_hayCambios,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _confirmarSalida();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_editando ? 'Editar tarea' : 'Nueva tarea')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _CampoElegible(
                icono: Icons.school_outlined,
                etiqueta: 'Curso',
                valor: curso?.nombre,
                colorMarca: curso == null ? null : Color(curso.color),
                error: faltan.contains('curso') ? 'Obligatorio' : null,
                onTap: () => _elegirCurso(cursos),
              ),
              _SelectorTipo(
                elegido: _borrador.tipo,
                falta: faltan.contains('tipo'),
                onChanged: (tipo) => setState(() => _borrador.tipo = tipo),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextFormField(
                  controller: _titulo,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  // setState para que PopScope sepa al instante si hay texto.
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Título (opcional)',
                    hintText: 'Ej.: Laboratorio 3',
                    prefixIcon: Icon(Icons.short_text),
                    border: OutlineInputBorder(),
                    // Oculta el contador "0/80": el límite se aplica igual.
                    counterText: '',
                  ),
                ),
              ),
              _CampoElegible(
                icono: Icons.event_outlined,
                etiqueta: 'Fecha',
                valor: fecha == null
                    ? null
                    : DateFormat("EEEE d 'de' MMMM 'de' y").format(fecha),
                error: faltan.contains('fecha') ? 'Obligatorio' : null,
                onTap: _elegirFecha,
              ),
              _CampoElegible(
                icono: Icons.schedule_outlined,
                etiqueta: 'Hora',
                valor: hora == null
                    ? null
                    : textoHora(DateTime(2000, 1, 1, hora.hour, hora.minute)),
                error: faltan.contains('hora')
                    ? 'Obligatorio'
                    : _horaYaPaso
                    ? 'Esa fecha y hora ya pasaron'
                    : null,
                onTap: _elegirHora,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextFormField(
                  controller: _peso,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Peso en la nota (opcional)',
                    hintText: 'Ej.: 20',
                    suffixText: '%',
                    prefixIcon: Icon(Icons.percent),
                    border: OutlineInputBorder(),
                  ),
                  validator: (texto) => validarPeso(texto ?? ''),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: const Icon(Icons.check),
              label: const Text('Guardar'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila que muestra un valor elegido (curso, fecha u hora) y se toca para
/// cambiarlo. Si hay un [error], se muestra en rojo.
class _CampoElegible extends StatelessWidget {
  const _CampoElegible({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    required this.onTap,
    this.error,
    this.colorMarca,
  });

  final IconData icono;
  final String etiqueta;
  final String? valor;
  final VoidCallback onTap;
  final String? error;
  final Color? colorMarca;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final marca = colorMarca;
    final mensajeError = error;
    return ListTile(
      leading: Icon(icono, color: mensajeError != null ? colores.error : null),
      title: Text(etiqueta),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (valor != null)
            Text(valor!, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (mensajeError != null)
            Text(mensajeError, style: TextStyle(color: colores.error))
          else if (valor == null)
            const Text('Toca para elegir'),
        ],
      ),
      trailing: marca == null
          ? const Icon(Icons.chevron_right)
          : CircleAvatar(radius: 10, backgroundColor: marca),
      onTap: onTap,
    );
  }
}

/// Chips para elegir el tipo de actividad.
class _SelectorTipo extends StatelessWidget {
  const _SelectorTipo({
    required this.elegido,
    required this.falta,
    required this.onChanged,
  });

  final TipoActividad? elegido;
  final bool falta;
  final ValueChanged<TipoActividad> onChanged;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            falta ? 'Tipo · Obligatorio' : 'Tipo',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: falta ? colores.error : null),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tipo in TipoActividad.values)
                ChoiceChip(
                  label: Text(tipo.etiqueta),
                  selected: tipo == elegido,
                  onSelected: (_) => onChanged(tipo),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
