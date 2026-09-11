// SLCAN / Lawicel ASCII protocol over a serial port.
// Covers CANable, CANtact, USBtin, Lawicel CAN232 and the many clones.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../can.dart';

// ---------------------------------------------------------------------------
// Protocol codec — pure string<->frame, no I/O, so it is unit-tested directly.
// ---------------------------------------------------------------------------

/// SLCAN offers a fixed bitrate table (S0..S8). Anything else needs the raw
/// BTR registers, which are chip-specific, so we expose only the standard set.
const slcanBitrateCodes = {
  10000: 'S0', 20000: 'S1', 50000: 'S2', 100000: 'S3', 125000: 'S4',
  250000: 'S5', 500000: 'S6', 800000: 'S7', 1000000: 'S8',
};

String encodeSlcan(CanFrame f) {
  final len = f.data.length.clamp(0, 8);
  final id = f.extended
      ? f.id.toRadixString(16).toUpperCase().padLeft(8, '0')
      : f.id.toRadixString(16).toUpperCase().padLeft(3, '0');
  final cmd = f.rtr
      ? (f.extended ? 'R' : 'r')
      : (f.extended ? 'T' : 't');
  final payload = f.rtr
      ? ''
      : f.data
          .take(len)
          .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .join();
  return '$cmd$id$len$payload\r';
}

/// Decode one SLCAN line (without the trailing CR).
///
/// Returns null for anything that is not a frame: version strings, status
/// replies, bare ACKs, and garbage from a half-open port.
CanFrame? parseSlcan(String line, {bool timestamps = false}) {
  if (line.isEmpty) return null;
  final kind = line[0];
  final extended = kind == 'T' || kind == 'R';
  final rtr = kind == 'r' || kind == 'R';
  if (!'tTrR'.contains(kind)) return null;

  final idLen = extended ? 8 : 3;
  if (line.length < 1 + idLen + 1) return null;

  final id = int.tryParse(line.substring(1, 1 + idLen), radix: 16);
  final dlc = int.tryParse(line.substring(1 + idLen, 2 + idLen), radix: 16);
  if (id == null || dlc == null || dlc > 8) return null;

  var pos = 2 + idLen;
  final data = Uint8List(rtr ? 0 : dlc);
  if (!rtr) {
    if (line.length < pos + dlc * 2) return null;
    for (var i = 0; i < dlc; i++) {
      final b = int.tryParse(line.substring(pos, pos + 2), radix: 16);
      if (b == null) return null;
      data[i] = b;
      pos += 2;
    }
  }

  Duration? hw;
  if (timestamps && line.length >= pos + 4) {
    final ms = int.tryParse(line.substring(pos, pos + 4), radix: 16);
    if (ms != null) hw = Duration(milliseconds: ms);
  }

  return CanFrame(
    id: id,
    data: data,
    extended: extended,
    rtr: rtr,
    hwTimestamp: hw,
  );
}

/// Split a raw serial chunk into complete CR-terminated lines, returning the
/// leftover partial line so the caller can prepend it to the next chunk.
(List<String>, String) splitSlcanLines(String buffer) {
  final parts = buffer.split('\r');
  final remainder = parts.removeLast();
  return (parts.where((p) => p.isNotEmpty).toList(), remainder);
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

class SlcanBus implements CanBus {
  SerialPort? _port;
  StreamSubscription<Uint8List>? _sub;
  final _frames = StreamController<CanFrame>.broadcast();
  final _status = StreamController<String>.broadcast();
  String _buffer = '';
  bool _timestamps = false;

  @override
  Stream<CanFrame> get frames => _frames.stream;
  @override
  Stream<String> get status => _status.stream;
  @override
  bool get isOpen => _port?.isOpen ?? false;

  @override
  Future<void> open(String address, int bitrate) async {
    final code = slcanBitrateCodes[bitrate];
    if (code == null) {
      throw CanBusException(
          'SLCAN adapters support only the standard bitrates '
          '${slcanBitrateCodes.keys.join(", ")}');
    }

    final port = SerialPort(address);
    if (!port.openReadWrite()) {
      throw CanBusException('Cannot open $address: ${SerialPort.lastError}');
    }
    // Most SLCAN adapters are USB CDC, where these settings are ignored, but
    // real RS-232 bridges (CAN232) need them.
    port.config = SerialPortConfig()
      ..baudRate = 115200
      ..bits = 8
      ..parity = SerialPortParity.none
      ..stopBits = 1
      ..setFlowControl(SerialPortFlowControl.none);
    _port = port;

    // Close first: an adapter left open by a crashed session ignores S/O.
    _write('C\r');
    await Future.delayed(const Duration(milliseconds: 50));
    _write('$code\r');
    await Future.delayed(const Duration(milliseconds: 20));
    _write('Z1\r'); // request timestamps; harmless if unsupported
    _timestamps = true;
    await Future.delayed(const Duration(milliseconds: 20));
    _write('O\r');

    _sub = SerialPortReader(port).stream.listen(
          _onData,
          onError: (Object e) => _status.add('serial error: $e'),
        );
  }

  void _onData(Uint8List chunk) {
    _buffer += String.fromCharCodes(chunk);
    final (lines, rest) = splitSlcanLines(_buffer);
    _buffer = rest;
    for (final line in lines) {
      if (line.codeUnitAt(0) == 7) {
        // BEL: adapter rejected the previous command or saw a bus error.
        _status.add('adapter reported an error (BEL)');
        continue;
      }
      final frame = parseSlcan(line, timestamps: _timestamps);
      if (frame != null) _frames.add(frame);
    }
  }

  void _write(String s) => _port?.write(Uint8List.fromList(s.codeUnits));

  @override
  Future<void> send(CanFrame frame) async {
    if (!isOpen) throw CanBusException('bus is not open');
    _write(encodeSlcan(frame));
  }

  @override
  Future<void> close() async {
    _write('C\r');
    await _sub?.cancel();
    _sub = null;
    _port?.close();
    _port?.dispose();
    _port = null;
  }
}

class SlcanBackend implements CanBackend {
  @override
  String get id => 'slcan';
  @override
  String get name => 'SLCAN (CANable, CANtact, USBtin, Lawicel)';
  @override
  bool get available => true; // libserialport ships with the app on all three OSes
  @override
  String get unavailableReason => '';

  @override
  Future<List<CanDevice>> discover() async {
    return SerialPort.availablePorts.map((p) {
      String label = p;
      try {
        final sp = SerialPort(p);
        final desc = sp.description;
        if (desc != null && desc.isNotEmpty) label = '$p — $desc';
        sp.dispose();
      } catch (_) {
        // Port vanished or is held by another process; the raw path still works.
      }
      return CanDevice(id, p, label);
    }).toList();
  }

  @override
  CanBus create() => SlcanBus();
}
