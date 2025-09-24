import 'package:get_it/get_it.dart';

import 'emergency_service.dart';
import 'mesh_network_service.dart';
import 'message_storage_service.dart';

/// Lightweight alternative to `service_locator.dart#setupServiceLocator()`.
///
/// Some early call sites still call `initializeServices()`; both flows
/// converge on the same GetIt singleton instance so they're safe to mix.
final getIt = GetIt.instance;

Future<void> initializeServices() async {
  if (!getIt.isRegistered<MeshNetworkService>()) {
    getIt.registerSingleton<MeshNetworkService>(MeshNetworkService());
  }

  if (!getIt.isRegistered<MessageStorageService>()) {
    final storage = MessageStorageService();
    await storage.initialize();
    getIt.registerSingleton<MessageStorageService>(storage);
  }

  if (!getIt.isRegistered<EmergencyService>()) {
    getIt.registerSingleton<EmergencyService>(EmergencyService());
  }

  await getIt<MeshNetworkService>().startScanning();
}

Future<void> cleanupServices() async {
  if (getIt.isRegistered<MeshNetworkService>()) {
    await getIt<MeshNetworkService>().stopScanning();
  }
  if (getIt.isRegistered<MessageStorageService>()) {
    await getIt<MessageStorageService>().close();
  }
  await getIt.reset();
}
