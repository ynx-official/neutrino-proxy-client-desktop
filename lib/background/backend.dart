import '../core/config.dart';

abstract interface class ClientBackend {
  Stream<Map<String, dynamic>> get events;
  Map<String, dynamic> get snapshot;
  Future<void> initialize();
  Future<void> connect();
  Future<void> disconnect();
  Future<void> save(
    ClientConfig config, {
    String? license,
    String? password,
    bool reconnect = false,
  });
  Future<void> close();
}
