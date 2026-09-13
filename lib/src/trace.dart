// Trace buffer and statistics.
//
// The hot path is [add], which is called once per received frame — at 1 Mbit
// that can be several thousand times a second. It does bookkeeping only; the
// UI is told to repaint on a fixed 20 Hz timer instead of per frame, because
// rebuilding a table per frame is what makes naive tracers unusable under load.
import 'dart:async';
import 'package:flutter/foundation.dart';

import 'can.dart';
import 'dbc.dart';

/// One row of the grouped ("fixed position") view: the latest state of an id.
class TraceRow {
  final int id;
  final bool extended;
  int count = 0;
  Uint8List data;
  FrameDirection direction;
  DateTime lastSeen;
  DateTime? prevSeen;

  /// Bytes that differed between the last two frames — drives change highlighting.
  int changedMask = 0;

  TraceRow(this.id, this.extended, this.data, this.lastSeen, this.direction);

  /// Mean interval over the last two occurrences, in milliseconds.
  double? get periodMs {
    final p = prevSeen;
    if (p == null) return null;
    return lastSeen.difference(p).inMicroseconds / 1000.0;
  }

  int get key => DbcDatabase.key(id, extended);
}

enum TraceView { live, grouped }

class TraceModel extends ChangeNotifier {
  /// ponytail: fixed-size ring of the most recent frames. A tracer that keeps
  /// every frame forever eventually eats all RAM; raise the cap or spill to
  /// disk if you need a long capture.
  static const liveCapacity = 20000;

  final List<CanFrame> _live = [];
  final Map<int, TraceRow> _rows = {};
  Timer? _repaint;

  DbcDatabase? dbc;
  String? dbcPath;

  bool paused = false;
  TraceView view = TraceView.grouped;

  // Filters
  String idFilter = '';

  // Statistics
  int totalFrames = 0;
  int _framesSinceTick = 0;
  double framesPerSecond = 0;
  int _bitsSinceTick = 0;
  double busLoadPercent = 0;
  int bitrate = 500000;
  final List<String> statusLog = [];

  TraceModel() {
    _repaint = Timer.periodic(const Duration(milliseconds: 50), _tick);
  }

  void _tick(Timer _) {
    framesPerSecond = _framesSinceTick * 20.0;
    busLoadPercent =
        bitrate == 0 ? 0 : (_bitsSinceTick * 20.0 / bitrate * 100).clamp(0, 100);
    _framesSinceTick = 0;
    _bitsSinceTick = 0;
    notifyListeners();
  }

  /// Nominal frame length on the wire, ignoring bit stuffing (which adds up to
  /// ~20% on pathological payloads). Good enough for a load indicator.
  static int frameBits(CanFrame f) =>
      (f.extended ? 67 : 47) + 8 * f.data.length;

  void add(CanFrame frame) {
    totalFrames++;
    _framesSinceTick++;
    _bitsSinceTick += frameBits(frame);
    if (paused) return;

    _live.add(frame);
    if (_live.length > liveCapacity) {
      _live.removeRange(0, _live.length - liveCapacity);
    }

    final key = DbcDatabase.key(frame.id, frame.extended);
    final existing = _rows[key];
    if (existing == null) {
      _rows[key] = TraceRow(
          frame.id, frame.extended, frame.data, frame.timestamp, frame.direction)
        ..count = 1;
    } else {
      var mask = 0;
      final n = frame.data.length;
      for (var i = 0; i < n; i++) {
        if (i >= existing.data.length || existing.data[i] != frame.data[i]) {
          mask |= 1 << i;
        }
      }
      existing
        ..changedMask = mask
        ..data = frame.data
        ..count += 1
        ..prevSeen = existing.lastSeen
        ..lastSeen = frame.timestamp
        ..direction = frame.direction;
    }
  }

  void addStatus(String message) {
    statusLog.add('${DateTime.now().toIso8601String().substring(11, 23)}  $message');
    if (statusLog.length > 500) statusLog.removeAt(0);
  }

  void clear() {
    _live.clear();
    _rows.clear();
    totalFrames = 0;
    notifyListeners();
  }

  void setPaused(bool v) {
    paused = v;
    notifyListeners();
  }

  void setView(TraceView v) {
    view = v;
    notifyListeners();
  }

  void setFilter(String text) {
    idFilter = text.trim();
    notifyListeners();
  }

  void loadDbc(DbcDatabase db, String path) {
    dbc = db;
    dbcPath = path;
    notifyListeners();
  }

  void clearDbc() {
    dbc = null;
    dbcPath = null;
    notifyListeners();
  }

  DbcMessage? messageFor(int id, bool extended) => dbc?.lookup(id, extended);

  /// Accepts an id filter of comma-separated hex ids and hex ranges,
  /// e.g. "123, 200-2FF". Empty means everything.
  static bool matchesIdFilter(int id, String filter) {
    if (filter.isEmpty) return true;
    for (final part in filter.split(',')) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final dash = p.indexOf('-');
      if (dash > 0) {
        final lo = int.tryParse(p.substring(0, dash).trim(), radix: 16);
        final hi = int.tryParse(p.substring(dash + 1).trim(), radix: 16);
        if (lo != null && hi != null && id >= lo && id <= hi) return true;
      } else {
        if (int.tryParse(p, radix: 16) == id) return true;
      }
    }
    return false;
  }

  bool _passes(int id, bool extended) => matchesIdFilter(id, idFilter);

  /// Newest first, so the interesting end is at the top and no scroll
  /// management is needed.
  List<CanFrame> get liveFrames {
    final out = <CanFrame>[];
    for (var i = _live.length - 1; i >= 0; i--) {
      final f = _live[i];
      if (_passes(f.id, f.extended)) out.add(f);
    }
    return out;
  }

  List<TraceRow> get groupedRows {
    final out = _rows.values.where((r) => _passes(r.id, r.extended)).toList();
    out.sort((a, b) {
      if (a.extended != b.extended) return a.extended ? 1 : -1;
      return a.id.compareTo(b.id);
    });
    return out;
  }

  /// CSV of the live buffer, in chronological order.
  String toCsv() {
    final b = StringBuffer('timestamp,direction,id,extended,dlc,data\n');
    for (final f in _live) {
      b.writeln('${f.timestamp.toIso8601String()},'
          '${f.direction.name},'
          '${f.idHex},'
          '${f.extended},'
          '${f.data.length},'
          '${f.dataHex.replaceAll(' ', '')}');
    }
    return b.toString();
  }

  @override
  void dispose() {
    _repaint?.cancel();
    super.dispose();
  }
}
