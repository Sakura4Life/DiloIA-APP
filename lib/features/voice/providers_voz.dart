import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'extraccion_api.dart';
import 'grabadora.dart';
import 'procesador_dictados.dart';

/// Pregunta al celular si está conectado a alguna red (wifi o datos).
///
/// Ojo: estar conectado a una red no garantiza que haya internet (por ejemplo,
/// un wifi sin saldo). Por eso, si la llamada a la IA falla por conexión, el
/// dictado igual queda en la cola.
class Conectividad {
  late final _conectividad = Connectivity();

  Future<bool> hayRed() async =>
      (await _conectividad.checkConnectivity()).hasConnectivity;

  /// Avisa cada vez que cambia la red: `true` si ahora hay alguna.
  Stream<bool> get cambios =>
      _conectividad.onConnectivityChanged.map((r) => r.hasConnectivity);
}

/// Las pruebas lo reemplazan, porque ahí no existe el plugin del celular.
final conectividadProvider = Provider<Conectividad>((ref) => Conectividad());

/// El micrófono. Las pruebas lo reemplazan por uno falso.
final grabadoraProvider = Provider<Grabadora>((ref) {
  final grabadora = Grabadora();
  ref.onDispose(grabadora.dispose);
  return grabadora;
});

/// Cliente de la Edge Function. Las pruebas lo reemplazan por uno falso.
final extraccionApiProvider = Provider<ExtraccionApi>((ref) {
  final api = ExtraccionApi();
  ref.onDispose(api.cerrar);
  return api;
});

/// Uno solo para toda la app, para que nunca se envíe el mismo dictado dos
/// veces a la vez.
final procesadorDictadosProvider = Provider<ProcesadorDictados>((ref) {
  final procesador = ProcesadorDictados(
    dictados: ref.watch(dictadosRepositoryProvider),
    cursos: ref.watch(coursesRepositoryProvider),
    api: ref.watch(extraccionApiProvider),
  );
  ref.onDispose(procesador.dispose);
  return procesador;
});
