/// Fecha de Lima en formato `YYYY-MM-DD`, que es como la espera la Edge
/// Function en el campo `hoy`.
///
/// Perú no tiene horario de verano: Lima siempre está 5 horas detrás de la
/// hora mundial (UTC). Así la fecha es la de Lima aunque el celular tenga otra
/// zona configurada. En la fase 6 se usará el paquete `timezone`.
String fechaEnLima(DateTime momento) {
  final lima = momento.toUtc().subtract(const Duration(hours: 5));
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${lima.year}-${dos(lima.month)}-${dos(lima.day)}';
}
