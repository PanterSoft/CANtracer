// Core CAN types. Pure Dart, no Flutter, no FFI — so everything here is testable.
import 'dart:typed_data';

enum FrameDirection { rx, tx }

class CanFrame {
  /// 11-bit or 29-bit identifier (without flag bits).
  final int id;
  final bool extended;
  final bool rtr;
  final Uint8List data;

  /// Host-side arrival time. Hardware timestamps, where a driver gives us one,
  /// are exposed separately via [hwTimestamp].
  final DateTime timestamp;
  final Duration? hwTimestamp;
  final FrameDirection direction;

  /// Channel index this frame came from, for multi-channel devices.
  final int channel;

  CanFrame({
    required this.id,
    required this.data,
    this.extended = false,
    this.rtr = false,
    DateTime? timestamp,
    this.hwTimestamp,
    this.direction = FrameDirection.rx,
    this.channel = 0,
  }) : timestamp = timestamp ?? DateTime.now();

  int get dlc => rtr ? data.length : data.length;

  String get idHex => extended
      ? id.toRadixString(16).toUpperCase().padLeft(8, '0')
      : id.toRadixString(16).toUpperCase().padLeft(3, '0');

  String get dataHex =>
      data.map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0')).join(' ');

  @override
  String toString() => '${extended ? 'x' : ''}$idHex [${data.length}] $dataHex';
}

/// Bitrates we offer in the UI. Every backend maps these to its own encoding.
const kStandardBitrates = [
  10000, 20000, 33333, 50000, 83333, 100000,
  125000, 250000, 500000, 800000, 1000000,
];

class CanDevice {
  /// Backend id, e.g. 'slcan', 'pcan', 'socketcan', 'vector', 'virtual'.
  final String backend;

  /// Opaque, backend-specific address (serial port path, channel handle, ifname).
  final String address;
  final String label;

  const CanDevice(this.backend, this.address, this.label);

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      other is CanDevice && other.backend == backend && other.address == address;

  @override
  int get hashCode => Object.hash(backend, address);
}

class CanBusException implements Exception {
  final String message;
  CanBusException(this.message);
  @override
  String toString() => 'CanBusException: $message';
}

/// What every hardware backend must provide. Keeping this surface tiny is what
/// makes adding a device family cheap and lets the UI stay backend-agnostic.
abstract class CanBus {
  Stream<CanFrame> get frames;

  /// Non-fatal driver notices (bus-off, error frames, rx overruns).
  Stream<String> get status;

  Future<void> open(String address, int bitrate);
  Future<void> close();
  Future<void> send(CanFrame frame);
  bool get isOpen;
}

/// Backends advertise themselves here so the UI never hardcodes a device list.
abstract class CanBackend {
  String get id;
  String get name;

  /// True when the platform and driver library are actually present.
  bool get available;

  /// Reason [available] is false — shown in the UI so a missing driver is
  /// diagnosable instead of the device list just being mysteriously empty.
  String get unavailableReason => '';

  Future<List<CanDevice>> discover();
  CanBus create();
}
