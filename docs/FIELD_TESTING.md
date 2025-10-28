# Field Testing Protocol

## Equipment Required
- 3-8 Android devices (SDK 21+) with Bluetooth 5.0
- 1 LoRa radio adapter (optional, for extended range tests)
- GPS-enabled device for location verification

## Test Scenarios

### Scenario 1: Urban Dense Mesh (BLE)
- **Setup**: 5 devices within 100m radius
- **Test**: Inject alert at node 1, verify delivery to all nodes
- **Expected**: <500ms delivery, 0% packet loss

### Scenario 2: Linear Relay Chain
- **Setup**: 4 devices in a line, 80m apart
- **Test**: Inject at first node, verify 3-hop delivery
- **Expected**: <1.5s delivery, <1% loss

### Scenario 3: Network Partition and Heal
- **Setup**: 6 devices in two clusters of 3
- **Test**: Inject alert, disable bridge node, re-enable, verify delayed delivery
- **Expected**: Store-and-forward delivers within 30s of healing

### Scenario 4: Battery Drain
- **Setup**: 2 devices, continuous mesh for 1 hour
- **Test**: Record battery drain per hour in each mode
- **Expected**: <5% drain in aggressive mode, <2% in power-saver

## Reporting
Record results in `test/results/field_test_YYYY-MM-DD.json` with:
- Device models and OS versions
- Test scenario and conditions
- Measured latency, packet loss, battery drain
- Any anomalies or failures observed
