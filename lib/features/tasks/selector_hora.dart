import 'package:flutter/material.dart';

import '../../core/formato.dart';

/// Convierte la hora del reloj de 12 horas (1–12, a. m./p. m.) a la de 24
/// horas que usa Flutter. Ej.: 12 a. m. → 0:00 y 12 p. m. → 12:00.
TimeOfDay horaDesde12({
  required int hora12,
  required int minuto,
  required bool pm,
}) {
  final base = hora12 % 12; // 12 se vuelve 0
  return TimeOfDay(hour: pm ? base + 12 : base, minute: minuto);
}

/// Hora del reloj de 12 horas (1–12) para una hora de 24.
int hora12De(TimeOfDay hora) => hora.hourOfPeriod == 0 ? 12 : hora.hourOfPeriod;

/// Abre la hoja para elegir la hora, al estilo de la app de alarmas del
/// teléfono. Devuelve `null` si el usuario cancela.
///
/// Si se pasa [fecha], el subtítulo dice cuánto falta para la tarea.
Future<TimeOfDay?> mostrarSelectorHora(
  BuildContext context, {
  required TimeOfDay inicial,
  DateTime? fecha,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SelectorHora(inicial: inicial, fecha: fecha),
  );
}

class _SelectorHora extends StatefulWidget {
  const _SelectorHora({required this.inicial, required this.fecha});

  final TimeOfDay inicial;
  final DateTime? fecha;

  @override
  State<_SelectorHora> createState() => _SelectorHoraState();
}

class _SelectorHoraState extends State<_SelectorHora> {
  late bool _pm = widget.inicial.period == DayPeriod.pm;
  late int _hora12 = hora12De(widget.inicial);
  late int _minuto = widget.inicial.minute;

  TimeOfDay get _elegida =>
      horaDesde12(hora12: _hora12, minuto: _minuto, pm: _pm);

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final textos = Theme.of(context).textTheme;
    final fecha = widget.fecha;

    // Subtítulo como el "Sonará en…" de la alarma: cuánto falta para la tarea.
    // El calendario no deja elegir días pasados, pero hoy sí se puede elegir
    // una hora que ya pasó; en ese caso se avisa en rojo.
    String? subtitulo;
    var yaPaso = false;
    if (fecha != null) {
      final momento = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        _elegida.hour,
        _elegida.minute,
      );
      subtitulo = textoFaltante(momento, ahora: DateTime.now());
      if (subtitulo == null) {
        subtitulo = 'Esa hora ya pasó';
        yaPaso = true;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Cancelar',
                iconSize: 28,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text('Elegir hora', style: textos.titleLarge),
                    if (subtitulo != null)
                      Text(
                        subtitulo,
                        style: textos.bodyMedium?.copyWith(
                          color: yaPaso
                              ? colores.error
                              : colores.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Aceptar',
                iconSize: 28,
                icon: const Icon(Icons.check),
                onPressed: () => Navigator.pop(context, _elegida),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              Expanded(child: _Etiqueta('h')),
              Expanded(child: _Etiqueta('min')),
            ],
          ),
          SizedBox(
            height: _Rueda.alto,
            child: Row(
              children: [
                Expanded(
                  child: _Rueda(
                    valores: const ['a. m.', 'p. m.'],
                    inicial: _pm ? 1 : 0,
                    ciclica: false,
                    tamanoLetra: 26,
                    onChanged: (i) => setState(() => _pm = i == 1),
                  ),
                ),
                Expanded(
                  child: _Rueda(
                    valores: [
                      for (var h = 1; h <= 12; h++)
                        h.toString().padLeft(2, '0'),
                    ],
                    inicial: _hora12 - 1,
                    ciclica: true,
                    onChanged: (i) => setState(() => _hora12 = i + 1),
                  ),
                ),
                Expanded(
                  child: _Rueda(
                    valores: [
                      for (var m = 0; m < 60; m++) m.toString().padLeft(2, '0'),
                    ],
                    inicial: _minuto,
                    ciclica: true,
                    onChanged: (i) => setState(() => _minuto = i),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

/// Una columna que gira como rueda. Muestra 5 valores: el elegido en el
/// centro, grande, y dos arriba y dos abajo, atenuados.
class _Rueda extends StatefulWidget {
  const _Rueda({
    required this.valores,
    required this.inicial,
    required this.ciclica,
    required this.onChanged,
    this.tamanoLetra = 44,
  });

  static const altoFila = 64.0;
  static const alto = altoFila * 5;

  final List<String> valores;
  final int inicial;

  /// Si al pasar el último valor se vuelve al primero (como 59 → 00).
  final bool ciclica;
  final ValueChanged<int> onChanged;
  final double tamanoLetra;

  @override
  State<_Rueda> createState() => _RuedaState();
}

class _RuedaState extends State<_Rueda> {
  late final _controller = FixedExtentScrollController(
    initialItem: widget.inicial,
  );
  late int _elegido = widget.inicial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    final hijos = [
      for (var i = 0; i < widget.valores.length; i++)
        Center(
          child: Text(
            widget.valores[i],
            style: TextStyle(
              fontSize: widget.tamanoLetra,
              fontWeight: i == _elegido ? FontWeight.w500 : FontWeight.w300,
              color: colores.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
    ];

    return ListWheelScrollView.useDelegate(
      controller: _controller,
      itemExtent: _Rueda.altoFila,
      physics: const FixedExtentScrollPhysics(),
      // Rueda casi plana y los valores lejanos del centro más tenues.
      diameterRatio: 3,
      overAndUnderCenterOpacity: 0.35,
      onSelectedItemChanged: (i) {
        // En la rueda cíclica el índice sigue creciendo al dar vueltas.
        final indice = i % widget.valores.length;
        setState(() => _elegido = indice);
        widget.onChanged(indice);
      },
      childDelegate: widget.ciclica
          ? ListWheelChildLoopingListDelegate(children: hijos)
          : ListWheelChildListDelegate(children: hijos),
    );
  }
}
