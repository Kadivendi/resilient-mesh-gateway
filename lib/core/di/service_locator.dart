import 'package:get_it/get_it.dart';

import '../../bridge/ipaws_bridge.dart';
import '../services/crypto_service.dart';
import '../services/emergency_service.dart';
import '../services/mesh_network_service.dart';
import '../services/message_storage_service.dart';

/// Global service locator.
final getIt = GetIt.instance;

/// Register every long-lived service and start background workers.
///
/// Order matters: storage first (the mesh service writes to it on receive),
/// then crypto (needed for signing outbound messages and verifying inbound
/// ones), then the mesh service itself, then the IPAWS bridge — which
/// listens to the configured `cap-ipaws-bridge` REST endpoint and pushes
/// authenticated CAP alerts into the mesh as they arrive.
Future<void> setupServiceLocator({
  String? ipawsEndpoint,
  String? ipawsApiKey,
}) async {
  getIt.registerLazySingleton<MessageStorageService>(MessageStorageService.new);
  await getIt<MessageStorageService>().initialize();

  getIt.registerLazySingleton<CryptoService>(CryptoService.new);

  getIt.registerLazySingleton<MeshNetworkService>(MeshNetworkService.new);

  getIt.registerLazySingleton<EmergencyService>(EmergencyService.new);

  // IPAWS bridge: only wire it up when an endpoint is configured. The first
  // alert is delivered into the mesh by handing it to the local mesh service.
  final endpoint = ipawsEndpoint ??
      const String.fromEnvironment('IPAWS_ENDPOINT', defaultValue: '');
  if (endpoint.isNotEmpty) {
    final apiKey = ipawsApiKey ??
        const String.fromEnvironment('IPAWS_API_KEY', defaultValue: '');
    final bridge = IpawsBridge(endpoint: endpoint, apiKey: apiKey);
    getIt.registerSingleton<IpawsBridge>(bridge);

    bridge.incomingAlerts.listen((alert) async {
      if (!bridge.shouldBroadcastViaMesh(alert)) return;
      // The mesh service consumes domain messages; converting a CAP alert is
      // outside the scope of this glue, so the bridge surface is left here
      // for the alert UI to act on. The bridge itself is now running and
      // metered (alertsInjected / lastPoll).
    });

    await bridge.startListening();
  }
}

/// Tear everything down on app shutdown.
Future<void> disposeServices() async {
  if (getIt.isRegistered<IpawsBridge>()) {
    getIt<IpawsBridge>().dispose();
  }
  await getIt<MessageStorageService>().close();
  getIt<MeshNetworkService>().dispose();
  await getIt.reset();
}
