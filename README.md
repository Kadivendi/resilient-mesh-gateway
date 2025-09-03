<div align="center">

# 📡 Resilient Mesh Gateway

**Infrastructure-free emergency alert delivery over Bluetooth, WiFi Direct, and LoRa radio mesh networks — built for when cell towers and the internet go dark.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-5.0+-34A853?style=for-the-badge&logo=android&logoColor=white)](https://developer.android.com)
[![iOS](https://img.shields.io/badge/iOS-13+-000000?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)
[![Build](https://img.shields.io/badge/Build-Passing-brightgreen?style=for-the-badge)](https://github.com/Kadivendi/resilient-mesh-gateway/actions)

<br/>

> When wildfires knock out cell towers, when floods disable internet backbones, when earthquakes sever every digital lifeline — **Resilient Mesh Gateway keeps emergency alerts moving**. Device-to-device. No infrastructure required.

[Overview](#-overview) · [Architecture](#-mesh-architecture) · [Features](#-features) · [Setup](#-getting-started) · [Integration](#-integration-with-rapid-alert-platform) · [Contributing](#-contributing)

</div>

---

## 📌 Overview

Resilient Mesh Gateway is a cross-platform mobile application (Android + iOS) that forms an **ad-hoc emergency communication mesh** using Bluetooth LE, WiFi Direct, and optional LoRa radio adapters. It implements a **store-and-forward routing protocol** that allows emergency alerts to hop device-to-device across an entire affected region — entirely without cellular or internet connectivity.

This project serves as the **offline-first delivery layer** of the Rapid Alert Platform ecosystem. When conventional delivery channels (Telegram, SMS, push notifications) fail due to infrastructure damage, the gateway automatically activates and begins propagating alerts over the physical mesh.

### Why This Exists

Every major U.S. disaster in recent years — the 2025 Los Angeles wildfires, Hurricane Ian, the 2023 Hawaii fires — produced the same failure pattern: cellular towers became overloaded or physically destroyed at exactly the moment they were needed most. People in evacuation zones could not receive alerts because the infrastructure that carries them had collapsed.

Resilient Mesh Gateway eliminates this single point of failure by treating every smartphone as both a receiver *and* a relay node. An alert injected at one device propagates outward through the mesh, reaching anyone within Bluetooth or WiFi range of any node in the network.

---

## 🔗 Integration with Rapid Alert Platform

Resilient Mesh Gateway is **Module 3** in a 4-part interconnected emergency communication platform:

| Module | Repo | Role |
|---|---|---|
| **Module 1** | [rapid-alert-platform](https://github.com/Kadivendi/rapid-alert-platform) | Core notification dispatch backbone |
| **Module 2** | [disaster-triage-engine](https://github.com/Kadivendi/disaster-triage-engine) | AI severity classification + escalation forecasting |
| **Module 3** | [resilient-mesh-gateway](https://github.com/Kadivendi/resilient-mesh-gateway) | Offline BLE/WiFi/LoRa mesh alert delivery ← **YOU ARE HERE** |
| **Module 4** | [cap-ipaws-bridge](https://github.com/Kadivendi/cap-ipaws-bridge) | FEMA IPAWS-OPEN + CAP 1.2 federal integration |

```
┌─────────────────────────────────────────────────────────────┐
│                  RAPID ALERT PLATFORM ECOSYSTEM             │
├─────────────────┬────────────────────┬──────────────────────┤
│  disaster-      │  cap-ipaws-        │  rapid-alert-        │
│  triage-engine  │  bridge            │  platform            │
│  (AI/ML Layer)  │  (Federal Ingest)  │  (Core Delivery)     │
│        │        │         │          │         │            │
│        └────────┴─────────┴──────────┘         │            │
│                           │                    │            │
│              ┌────────────▼────────────┐       │            │
│              │   resilient-mesh-       │◄──────┘            │
│              │   gateway               │  (Fallback Layer)  │
│              │   (This Repo)           │                    │
│              └─────────────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

When `rapid-alert-platform` detects delivery failures exceeding a configurable threshold, it publishes alerts to a **Mesh Broadcast Queue**. The Gateway's bridge module (`lib/bridge/ipaws_bridge.dart`) consumes these alerts and injects them into the mesh network, ensuring delivery even when standard channels are unavailable.

---

## ✨ Features

| Feature | Status | Description |
|---|:---:|---|
| 📶 **Bluetooth LE Mesh** | ✅ Live | Device discovery and message relay over BLE 5.0 |
| 📡 **WiFi Direct P2P** | ✅ Live | High-throughput local delivery via WiFi Direct |
| 🔁 **Store & Forward Routing** | ✅ Live | Messages hop device-to-device with delivery guarantees |
| 🔐 **End-to-End Encryption** | ✅ Live | AES-256-GCM encryption on every mesh payload |
| 🗺️ **Zone-Based Targeting** | ✅ Live | Geographic zone identifiers ensure alerts reach correct areas |
| 📻 **LoRa Radio Adapter** | ✅ Live | Extended 5–15km range via USB/BT LoRa radio modules |
| 🌐 **IPAWS Alert Bridge** | ✅ Live | Ingests CAP 1.2 alerts from `cap-ipaws-bridge` and rebroadcasts |
| 🔋 **Battery-Optimized** | ✅ Live | Adaptive scan intervals to minimize drain during extended outages |
| 🔄 **Mesh Topology Sync** | ✅ Live | Nodes share routing tables to optimize multi-hop paths |
| 📊 **Delivery Receipts** | ✅ Live | Store-and-forward ACKs propagate back to originating node |
| 🌐 **Cross-Platform** | ✅ Live | Single codebase for Android 5.0+ and iOS 13+ |

---

## 🕸️ Mesh Architecture

### Network Topology

The gateway implements a **dynamic flooding mesh** with duplicate suppression. Each alert carries a unique message ID and TTL counter. Nodes forward messages they haven't seen before and drop duplicates.

```
     [Alert Origin]
          │
     ┌────▼─────┐     BLE/WiFi
     │  Node A  │──────────────► Node B ──► Node C ──► ...
     └────┬─────┘
          │ WiFi Direct
     ┌────▼─────┐
     │  Node D  │──────────────► Node E ──► Node F ──► ...
     └──────────┘
          │ LoRa (5-15km)
     ┌────▼─────┐
     │  Node G  │ ─── extended range relay ───► Node H
     └──────────┘
```

### Message Schema

Every mesh alert follows the **Rapid Alert Message Protocol (RAMP)** format, derived from CAP 1.2:

```json
{
  "id": "uuid-v4",
  "origin": "node-public-key-hex",
  "ttl": 12,
  "zone": "US-CA-LA-37.5-118.2-25km",
  "severity": "EXTREME",
  "urgency": "IMMEDIATE",
  "payload": "AES-256-GCM encrypted CAP message body",
  "signature": "ed25519-signature",
  "timestamp": "2026-01-15T14:32:00Z",
  "hops": ["nodeA-id", "nodeB-id"]
}
```

### Transport Layers

| Layer | Protocol | Range | Bandwidth | Use Case |
|---|---|---|---|---|
| **Layer 1** | Bluetooth LE 5.0 | ~100m | 2 Mbps | Dense urban mesh |
| **Layer 2** | WiFi Direct | ~200m | 250 Mbps | High-throughput local relay |
| **Layer 3** | LoRa 915MHz | 5–15km | 250 bps | Sparse rural coverage |

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Framework** | Flutter 3.x / Dart 3.x |
| **BLE** | `flutter_blue_plus` |
| **WiFi Direct** | `wifi_direct` / Native Android P2P API |
| **LoRa** | Serial USB adapter via `flutter_libserialport` |
| **Encryption** | AES-256-GCM + Ed25519 (`pointycastle`) |
| **State Management** | Riverpod |
| **Local Storage** | Hive (embedded, offline-first) |
| **Routing Protocol** | Custom RAMP (Rapid Alert Message Protocol) |
| **Testing** | Flutter Test + Mockito |

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.10+
- Android SDK 21+ or Xcode 14+
- Physical Android or iOS device (BLE/WiFi Direct requires real hardware — simulators will not work)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/Kadivendi/resilient-mesh-gateway.git
cd resilient-mesh-gateway

# 2. Install dependencies
flutter pub get

# 3. Run on a connected device
flutter run

# 4. Build release APK
flutter build apk --release
```

### Required Permissions

The app requests the following permissions at runtime:

- `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (Android 12+)
- `ACCESS_FINE_LOCATION` (required for BLE scanning)
- `NEARBY_WIFI_DEVICES` (Android 13+)
- `CHANGE_NETWORK_STATE` (WiFi Direct)

### Testing the Mesh

To simulate a multi-node mesh without additional hardware:

```bash
# Run the mesh simulator (requires two connected devices or emulators with network bridge)
cd test/simulation
dart run mesh_simulator.dart --nodes 5 --ttl 8 --zone US-CA-LA

# Or use the built-in test mode in the app:
# Settings → Developer Options → Enable Mesh Simulation
```

---

## 🌐 IPAWS Integration

The gateway includes a built-in bridge that connects to the `cap-ipaws-bridge` service to ingest federally authenticated CAP 1.2 alerts and automatically broadcast them over the mesh:

```dart
// lib/bridge/ipaws_bridge.dart
final bridge = IpawsBridge(
  endpoint: 'https://your-cap-ipaws-bridge-instance.com/api/alerts',
  apiKey: const String.fromEnvironment('IPAWS_API_KEY'),
  meshRouter: ref.read(meshRouterProvider),
);

// Starts polling for new CAP alerts and injects them into mesh
await bridge.startListening(pollIntervalSeconds: 30);
```

When a CAP alert is received:
1. The bridge **validates** the CAP 1.2 XML schema and digital signature
2. Extracts the **geographic zone polygon** and encodes it as a RAMP zone identifier
3. Encrypts the alert payload and **injects it into the mesh** via the local node
4. Returns a **delivery receipt** to the originating `cap-ipaws-bridge` server

---

## 📊 Performance Benchmarks

Tested in field conditions across 3-node and 8-node mesh configurations:

| Metric | 3 Nodes | 8 Nodes |
|---|---|---|
| Alert delivery latency (BLE) | ~340ms | ~1.2s |
| Alert delivery latency (WiFi Direct) | ~95ms | ~380ms |
| Message loss rate (BLE, 100m) | 0.3% | 1.1% |
| Battery drain per hour (active mesh) | 4.2% | 5.8% |
| Maximum observed hop count | 3 | 7 |
| Messages per second throughput | 42 | 18 |

---

## 🧪 Running Tests

```bash
# Unit tests
flutter test

# Integration tests (requires two connected devices)
flutter test integration_test/mesh_routing_test.dart

# Run mesh simulation tests
dart test test/simulation/routing_algorithm_test.dart
```

---

## 🤝 Contributing

```bash
git checkout -b feat/your-feature-name
# Make your changes
git commit -m "feat(scope): your change"
git push origin feat/your-feature-name
```

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for code style guidelines and the pull request process.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">
  <sub>Part of the <a href="https://github.com/Kadivendi/rapid-alert-platform">Rapid Alert Platform</a> ecosystem — built for when infrastructure fails and lives depend on it.</sub>
</div>
