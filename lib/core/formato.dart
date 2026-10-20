import 'package:intl/intl.dart';

/// Título de un grupo de días en la lista: "Hoy", "Mañana", "Ayer" o la fecha
/// completa ("Lunes 6 de octubre"). Agrega el año solo si no es el actual.
String etiquetaDia(DateTime fecha, {required DateTime hoy}) {
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final base = DateTime(hoy.year, hoy.month, hoy.day);
  // Se usa la diferencia en horas redondeada porque un cambio de horario de
  // verano haría que un día "dure" 23 o 25 horas.
  final diferencia = (dia.difference(base).inHours / 24).round();

  switch (diferencia) {
    case 0:
      return 'Hoy';
    case 1:
      return 'Mañana';
    case -1:
      return 'Ayer';
  }
  final patron = fecha.year == hoy.year
      ? "EEEE d 'de' MMMM"
      : "EEEE d 'de' MMMM 'de' y";
  final texto = DateFormat(patron).format(fecha);
  return texto[0].toUpperCase() + texto.substring(1);
}

/// Cuánto falta para [momento], como en el reloj al programar una alarma:
/// "Faltan 2 días y 3 horas", "Falta 1 hora y 5 minutos". Devuelve `null` si
/// el momento ya pasó.
String? textoFaltante(DateTime momento, {required DateTime ahora}) {
  if (!momento.isAfter(ahora)) return null;
  // Se redondea hacia arriba: si faltan 30 segundos, se dice "1 minuto".
  final minutos = (momento.difference(ahora).inSeconds / 60).ceil();
  final dias = minutos ~/ (24 * 60);
  final horas = (minutos % (24 * 60)) ~/ 60;
  final mins = minutos % 60;

  String unidad(int n, String singular, String plural) =>
      '$n ${n == 1 ? singular : plural}';

  final (int primero, String texto) = switch ((dias, horas)) {
    (> 0, > 0) => (
      dias,
      '${unidad(dias, 'día', 'días')} y ${unidad(horas, 'hora', 'horas')}',
    ),
    (> 0, _) => (dias, unidad(dias, 'día', 'días')),
    (_, > 0) when mins > 0 => (
      horas,
      '${unidad(horas, 'hora', 'horas')} y ${unidad(mins, 'minuto', 'minutos')}',
    ),
    (_, > 0) => (horas, unidad(horas, 'hora', 'horas')),
    _ => (mins, unidad(mins, 'minuto', 'minutos')),
  };
  return '${primero == 1 ? 'Falta' : 'Faltan'} $texto';
}

/// Hora en formato de 12 horas, como en un reloj: "4:00 p. m.".
String textoHora(DateTime momento) => DateFormat('h:mm a').format(momento);

/// "4:00 p. m. – 6:00 p. m.": de cuándo a cuándo es un evento.
String textoLapso(DateTime inicio, DateTime fin) =>
    '${textoHora(inicio)} – ${textoHora(fin)}';

/// "2 h", "1 h 30 min" o "45 min".
String textoDuracion(Duration duracion) {
  final horas = duracion.inHours;
  final minutos = duracion.inMinutes % 60;
  if (horas == 0) return '$minutos min';
  if (minutos == 0) return '$horas h';
  return '$horas h $minutos min';
}

/// "20" o "12,5": sin decimales cuando el número es entero, y con coma
/// decimal como se escribe en español.
String numeroPeso(double peso) {
  return peso == peso.roundToDouble()
      ? peso.toInt().toString()
      : peso.toString().replaceAll('.', ',');
}

/// "20%" o "12,5%".
String textoPeso(double peso) => '${numeroPeso(peso)}%';
