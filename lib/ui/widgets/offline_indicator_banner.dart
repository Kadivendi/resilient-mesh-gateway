import 'package:flutter/material.dart';

/// Persistent top banner that indicates mesh-only mode when internet is unavailable.
/// Animates in/out smoothly based on connectivity state.
class OfflineIndicatorBanner extends StatelessWidget {
  final bool isOffline;
  final int meshPeerCount;
  final String? activeTransport; // 'ble', 'wifi_direct', 'lora'

  const OfflineIndicatorBanner({
    super.key,
    required this.isOffline,
    this.meshPeerCount = 0,
    this.activeTransport,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      height: isOffline ? 44.0 : 0.0,
      color: _bannerColor,
      child: isOffline
          ? SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_transportIcon, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _bannerText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (meshPeerCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$meshPeerCount peers',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Color get _bannerColor {
    if (meshPeerCount == 0) return const Color(0xFFB71C1C); // red — isolated
    return const Color(0xFFE65100); // orange — mesh active
  }

  IconData get _transportIcon {
    switch (activeTransport) {
      case 'lora': return Icons.cell_tower;
      case 'wifi_direct': return Icons.wifi;
      default: return Icons.bluetooth;
    }
  }

  String get _bannerText {
    if (meshPeerCount == 0) return '⚠ No internet — mesh searching...';
    final transport = activeTransport?.replaceAll('_', ' ').toUpperCase() ?? 'BLE';
    return '⚡ Mesh mode active via $transport';
  }
}
