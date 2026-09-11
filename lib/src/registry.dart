import 'can.dart';
import 'backends/pcan.dart';
import 'backends/slcan.dart';
import 'backends/socketcan.dart';
import 'backends/vector.dart';
import 'backends/virtual.dart';

/// Every backend the app knows about. Adding a device family means adding one
/// CanBackend here — nothing in the UI changes.
final backends = <CanBackend>[
  SlcanBackend(),
  SocketCanBackend(),
  PcanBackend(),
  VectorBackend(),
  VirtualBackend(),
];

CanBackend backendById(String id) =>
    backends.firstWhere((b) => b.id == id, orElse: () => VirtualBackend());

/// Discover across all available backends at once, tolerating a backend that
/// throws because its driver is half-installed.
Future<List<CanDevice>> discoverAll() async {
  final out = <CanDevice>[];
  for (final b in backends) {
    if (!b.available) continue;
    try {
      out.addAll(await b.discover());
    } catch (_) {
      // A broken driver must not hide the working ones.
    }
  }
  return out;
}
