import 'package:flutter/material.dart';

import '../../core/course_colors.dart';
import '../../data/courses_repository.dart';

/// Lo que devuelve el diálogo al guardar: el nombre y el color elegidos.
typedef DatosCurso = ({String nombre, int color});

/// Abre el diálogo para crear o editar un curso. Devuelve `null` si el usuario
/// cancela. [nombresExistentes] sirve para no permitir cursos repetidos.
Future<DatosCurso?> mostrarDialogoCurso(
  BuildContext context, {
  required List<String> nombresExistentes,
  String nombreInicial = '',
  int? colorInicial,
}) {
  return showDialog<DatosCurso>(
    context: context,
    builder: (_) => _DialogoCurso(
      nombresExistentes: nombresExistentes,
      nombreInicial: nombreInicial,
      colorInicial: colorInicial,
    ),
  );
}

class _DialogoCurso extends StatefulWidget {
  const _DialogoCurso({
    required this.nombresExistentes,
    required this.nombreInicial,
    required this.colorInicial,
  });

  final List<String> nombresExistentes;
  final String nombreInicial;
  final int? colorInicial;

  @override
  State<_DialogoCurso> createState() => _DialogoCursoState();
}

class _DialogoCursoState extends State<_DialogoCurso> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.nombreInicial);
  late int _color = widget.colorInicial ?? coloresDeCurso.first.toARGB32();

  bool get _esNuevo => widget.nombreInicial.isEmpty;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  String? _validarNombre(String? texto) {
    final nombre = texto?.trim() ?? '';
    if (nombre.isEmpty) return 'Escribe el nombre del curso';
    if (nombre.length > 60) return 'Máximo 60 caracteres';
    // Al editar, el propio nombre original no cuenta como repetido.
    final repetido = widget.nombresExistentes.any(
      (otro) =>
          claveDeOrden(otro) == claveDeOrden(nombre) &&
          claveDeOrden(otro) != claveDeOrden(widget.nombreInicial),
    );
    if (repetido) return 'Ya tienes un curso con ese nombre';
    return null;
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop<DatosCurso>(context, (
      nombre: _nombre.text.trim(),
      color: _color,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esNuevo ? 'Nuevo curso' : 'Editar curso'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nombre,
              autofocus: _esNuevo,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej.: Física I',
              ),
              validator: _validarNombre,
              onFieldSubmitted: (_) => _guardar(),
            ),
            const SizedBox(height: 20),
            Text('Color', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in coloresDeCurso)
                  _MuestraColor(
                    color: color,
                    elegido: color.toARGB32() == _color,
                    onTap: () => setState(() => _color = color.toARGB32()),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

class _MuestraColor extends StatelessWidget {
  const _MuestraColor({
    required this.color,
    required this.elegido,
    required this.onTap,
  });

  final Color color;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegido,
      label: 'Color del curso',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: color,
          child: elegido
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}
