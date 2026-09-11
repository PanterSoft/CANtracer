import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/backends/slcan.dart';
import 'src/can.dart';
import 'src/dbc.dart';
import 'src/registry.dart';
import 'src/trace.dart';
import 'src/update.dart';

void main() => runApp(const CanTracerApp());

const _mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Consolas'], fontSize: 13);

class CanTracerApp extends StatelessWidget {
  const CanTracerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CANtracer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3DDC84),
          brightness: Brightness.dark,
        ),
        visualDensity: VisualDensity.compact,
      ),
      home: const TracerPage(),
    );
  }
}

class TracerPage extends StatefulWidget {
  const TracerPage({super.key});
  @override
  State<TracerPage> createState() => _TracerPageState();
}

class _TracerPageState extends State<TracerPage> {
  final model = TraceModel();
  CanBus? bus;
  CanDevice? device;
  int bitrate = 500000;
  List<CanDevice> devices = [];
  bool connecting = false;
  bool scanning = false;
  final expanded = <int>{};

  @override
  void initState() {
    super.initState();
    _refreshDevices();
    checkForUpdate().then((tag) {
      if (tag == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('CANtracer $tag is available (installed: $appVersion)'),
        duration: const Duration(seconds: 15),
        action: SnackBarAction(label: 'Download', onPressed: openReleasePage),
      ));
    });
  }

  @override
  void dispose() {
    bus?.close();
    model.dispose();
    super.dispose();
  }

  Future<void> _refreshDevices() async {
    setState(() => scanning = true);
    final found = await discoverAll();
    if (!mounted) return;
    final hw = found.where((d) => d.backend != 'virtual').length;
    model.addStatus(hw == 0
        ? 'scan: no CAN interfaces found (virtual bus only)'
        : 'scan: $hw CAN interface${hw == 1 ? '' : 's'} found');
    setState(() {
      scanning = false;
      devices = found;
      if (device != null && !found.contains(device)) device = null;
      device ??= found.isNotEmpty ? found.first : null;
    });
  }

  Future<void> _connect() async {
    final d = device;
    if (d == null) return;
    setState(() => connecting = true);
    try {
      final b = backendById(d.backend).create();
      b.frames.listen(model.add);
      b.status.listen(model.addStatus);
      await b.open(d.address, bitrate);
      model.bitrate = bitrate;
      model.addStatus('connected to ${d.label} at $bitrate bit/s');
      setState(() => bus = b);
    } catch (e) {
      model.addStatus('$e');
      if (mounted) _toast('$e');
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> _disconnect() async {
    await bus?.close();
    model.addStatus('disconnected');
    setState(() => bus = null);
  }

  Future<void> _loadDbc() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Open DBC database');
    if (file == null) return;
    try {
      // DBCs from older tools are latin-1; allowMalformed keeps those readable.
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final db = parseDbc(text);
      model.loadDbc(db, file.name);
      model.addStatus('loaded ${file.name}: '
          '${db.messageCount} messages, ${db.signalCount} signals');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _exportCsv() async {
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export trace as CSV',
      fileName: 'cantrace.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode(model.toCsv()),
    );
    if (uri != null) _toast('Exported to ${uri.toFilePath()}');
  }

  // The toolbar and tables live in separate widgets; these are the only
  // pieces of page state they mutate.
  void toggleExpanded(int key) =>
      setState(() => expanded.contains(key) ? expanded.remove(key) : expanded.add(key));
  void expandAll(bool expand) => setState(() {
        expanded.clear();
        if (expand) {
          expanded.addAll(model.groupedRows
              .where((r) => model.messageFor(r.id, r.extended) != null)
              .map((r) => r.key));
        }
      });
  void setDevice(CanDevice? d) => setState(() => device = d);
  void setBitrate(int b) => setState(() => bitrate = b);
  void setProbeSerial(bool v) {
    (backendById('slcan') as SlcanBackend).probe = v;
    _refreshDevices();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), showCloseIcon: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _Toolbar(state: this),
          const Divider(height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: model,
              builder: (context, _) => model.view == TraceView.grouped
                  ? _GroupedTable(state: this)
                  : _LiveTable(state: this),
            ),
          ),
          const Divider(height: 1),
          ListenableBuilder(
            listenable: model,
            builder: (context, _) => _StatusBar(model: model),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  final _TracerPageState state;
  const _Toolbar({required this.state});

  @override
  Widget build(BuildContext context) {
    final connected = state.bus != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('CANtracer',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 8),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<CanDevice>(
              initialValue: state.device,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Interface',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: state.devices
                  .map((d) => DropdownMenuItem(
                      value: d,
                      child: Text(d.label, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged:
                  connected ? null : state.setDevice,
            ),
          ),
          IconButton(
            tooltip: 'Rescan for devices',
            onPressed: connected || state.scanning ? null : state._refreshDevices,
            icon: state.scanning
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
          FilterChip(
            tooltip: 'List every serial port instead of only detected CAN adapters',
            label: const Text('All ports'),
            selected: !(backendById('slcan') as SlcanBackend).probe,
            onSelected: connected ? null : (v) => state.setProbeSerial(!v),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<int>(
              initialValue: state.bitrate,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Bitrate',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: kStandardBitrates
                  .map((b) => DropdownMenuItem(
                      value: b, child: Text('${b ~/ 1000} kbit/s', overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: connected ? null : (b) => state.setBitrate(b!),
            ),
          ),
          FilledButton.icon(
            onPressed: state.connecting
                ? null
                : connected
                    ? state._disconnect
                    : state._connect,
            icon: Icon(connected ? Icons.stop : Icons.play_arrow),
            label: Text(connected ? 'Disconnect' : 'Connect'),
          ),
          const SizedBox(width: 12),
          SegmentedButton<TraceView>(
            segments: const [
              ButtonSegment(
                  value: TraceView.grouped,
                  icon: Icon(Icons.view_list),
                  label: Text('Grouped')),
              ButtonSegment(
                  value: TraceView.live,
                  icon: Icon(Icons.stream),
                  label: Text('Live')),
            ],
            selected: {state.model.view},
            onSelectionChanged: (s) => state.model.setView(s.first),
          ),
          IconButton.filledTonal(
            tooltip: state.model.paused ? 'Resume' : 'Pause',
            onPressed: () => state.model.setPaused(!state.model.paused),
            icon: Icon(state.model.paused ? Icons.play_arrow : Icons.pause),
          ),
          IconButton.filledTonal(
            tooltip: 'Clear trace',
            onPressed: state.model.clear,
            icon: const Icon(Icons.delete_sweep),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: state._loadDbc,
            icon: const Icon(Icons.description),
            label: const Text('Load DBC'),
          ),
          if (state.model.dbc != null)
            IconButton(
              tooltip: 'Unload ${state.model.dbcPath}',
              onPressed: state.model.clearDbc,
              icon: const Icon(Icons.close),
            ),
          OutlinedButton.icon(
            onPressed: state._exportCsv,
            icon: const Icon(Icons.save_alt),
            label: const Text('Export CSV'),
          ),
          OutlinedButton.icon(
            onPressed: connected
                ? () => showDialog(
                    context: context,
                    builder: (_) => _SendDialog(state: state))
                : null,
            icon: const Icon(Icons.send),
            label: const Text('Send'),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'ID filter (hex)',
                hintText: '100, 200-2FF',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: state.model.setFilter,
            ),
          ),
          FilterChip(
            label: const Text('DBC only'),
            selected: state.model.onlyKnown,
            onSelected: state.model.setOnlyKnown,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

const _headerStyle = TextStyle(
    fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9E9E9E));

Widget _header(List<(String, int)> cols) => Container(
      color: const Color(0x22FFFFFF),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          for (final (label, flex) in cols)
            Expanded(flex: flex, child: Text(label, style: _headerStyle)),
        ],
      ),
    );

/// Hex payload with per-byte highlighting of what just changed.
class _HexData extends StatelessWidget {
  final Uint8List data;
  final int changedMask;
  const _HexData(this.data, {this.changedMask = 0});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (var i = 0; i < data.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              data[i].toRadixString(16).toUpperCase().padLeft(2, '0'),
              style: _mono.copyWith(
                color: (changedMask >> i) & 1 == 1 ? accent : null,
                fontWeight:
                    (changedMask >> i) & 1 == 1 ? FontWeight.bold : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// A line in the grouped trace: either a message or, when that message is
/// expanded and decodable, one of its signals — CANoe's trace window layout.
sealed class _Line {}

class _MsgLine extends _Line {
  final TraceRow row;
  final DbcMessage? msg;
  _MsgLine(this.row, this.msg);
}

class _SigLine extends _Line {
  final TraceRow row;
  final DbcSignal sig;
  _SigLine(this.row, this.sig);
}

class _GroupedTable extends StatelessWidget {
  final _TracerPageState state;
  const _GroupedTable({required this.state});

  @override
  Widget build(BuildContext context) {
    final model = state.model;
    final lines = <_Line>[];
    for (final r in model.groupedRows) {
      final msg = model.messageFor(r.id, r.extended);
      lines.add(_MsgLine(r, msg));
      if (msg != null && state.expanded.contains(r.key)) {
        for (final sig in msg.signalsFor(r.data)) {
          lines.add(_SigLine(r, sig));
        }
      }
    }
    final anyExpanded = state.expanded.isNotEmpty;

    return Column(
      children: [
        Container(
          color: const Color(0x22FFFFFF),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          child: Row(
            children: [
              IconButton(
                tooltip: anyExpanded ? 'Collapse all' : 'Expand all',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: model.dbc == null ? null : () => state.expandAll(!anyExpanded),
                icon: Icon(anyExpanded ? Icons.unfold_less : Icons.unfold_more),
              ),
              const Expanded(flex: 2, child: Text('ID', style: _headerStyle)),
              const Expanded(flex: 4, child: Text('MESSAGE / SIGNAL', style: _headerStyle)),
              const Expanded(flex: 1, child: Text('LEN', style: _headerStyle)),
              const Expanded(flex: 6, child: Text('DATA / VALUE', style: _headerStyle)),
              const Expanded(flex: 2, child: Text('COUNT / RAW', style: _headerStyle)),
              const Expanded(flex: 2, child: Text('CYCLE', style: _headerStyle)),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? const _Empty('No frames yet — connect an interface.')
              : ListView.builder(
                  itemCount: lines.length,
                  itemExtent: 28,
                  itemBuilder: (context, i) => switch (lines[i]) {
                    _MsgLine l => _messageRow(context, l),
                    _SigLine l => _signalRow(context, l),
                  },
                ),
        ),
      ],
    );
  }

  Widget _messageRow(BuildContext context, _MsgLine l) {
    final r = l.row;
    final msg = l.msg;
    final theme = Theme.of(context);
    final open = state.expanded.contains(r.key);
    final period = r.periodMs;
    return InkWell(
      onTap: msg == null ? null : () => state.toggleExpanded(r.key),
      child: Container(
        color: open ? theme.colorScheme.primary.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.only(left: 4, right: 12),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: msg == null
                  ? null
                  : Icon(open ? Icons.arrow_drop_down : Icons.arrow_right,
                      size: 20, color: theme.colorScheme.primary),
            ),
            Expanded(
                flex: 2,
                child: Text('${r.extended ? "x" : ""}${_hexId(r.id, r.extended)}',
                    style: _mono)),
            Expanded(
                flex: 4,
                child: Text(msg?.name ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: msg == null ? Colors.grey : theme.colorScheme.primary))),
            Expanded(flex: 1, child: Text('${r.data.length}', style: _mono)),
            Expanded(flex: 6, child: _HexData(r.data, changedMask: r.changedMask)),
            Expanded(flex: 2, child: Text('${r.count}', style: _mono)),
            Expanded(
                flex: 2,
                child: Text(period == null ? '—' : '${period.toStringAsFixed(1)} ms',
                    style: _mono)),
          ],
        ),
      ),
    );
  }

  Widget _signalRow(BuildContext context, _SigLine l) {
    final s = l.sig;
    final data = l.row.data;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 12),
      child: Row(
        children: [
          const SizedBox(width: 40),
          const Expanded(flex: 2, child: SizedBox()),
          Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text('└ ${s.name}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              )),
          const Expanded(flex: 1, child: SizedBox()),
          Expanded(
              flex: 6,
              child: Text(s.format(data),
                  style: _mono.copyWith(fontWeight: FontWeight.bold))),
          Expanded(
              flex: 2,
              child: Text('${s.rawFrom(data)}',
                  style: _mono.copyWith(color: Colors.grey))),
          Expanded(
              flex: 2,
              child: Text(
                  '${s.startBit}|${s.length}@${s.byteOrder == ByteOrder.intel ? 1 : 0}${s.signed ? "-" : "+"}',
                  style: _mono.copyWith(color: Colors.grey, fontSize: 11))),
        ],
      ),
    );
  }
}

class _LiveTable extends StatelessWidget {
  final _TracerPageState state;
  const _LiveTable({required this.state});

  @override
  Widget build(BuildContext context) {
    final frames = state.model.liveFrames;
    return Column(
      children: [
        _header(const [
          ('TIME', 3), ('DIR', 1), ('ID', 2), ('MESSAGE', 4), ('LEN', 1), ('DATA', 6),
        ]),
        Expanded(
          child: frames.isEmpty
              ? const _Empty('No frames yet — connect an interface.')
              : ListView.builder(
                  itemCount: frames.length,
                  itemExtent: 26,
                  itemBuilder: (context, i) {
                    final f = frames[i];
                    final msg = state.model.messageFor(f.id, f.extended);
                    final tx = f.direction == FrameDirection.tx;
                    return InkWell(
                      onTap: null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Text(
                                    f.timestamp
                                        .toIso8601String()
                                        .substring(11, 23),
                                    style: _mono.copyWith(color: Colors.grey))),
                            Expanded(
                                flex: 1,
                                child: Text(tx ? 'Tx' : 'Rx',
                                    style: _mono.copyWith(
                                        color: tx ? Colors.orangeAccent : null))),
                            Expanded(
                                flex: 2,
                                child: Text(
                                    '${f.extended ? "x" : ""}${_hexId(f.id, f.extended)}',
                                    style: _mono)),
                            Expanded(
                                flex: 4,
                                child: Text(msg?.name ?? '—',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: msg == null
                                            ? Colors.grey
                                            : Theme.of(context).colorScheme.primary))),
                            Expanded(
                                flex: 1,
                                child: Text('${f.data.length}', style: _mono)),
                            Expanded(flex: 6, child: _HexData(f.data)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

String _hexId(int id, bool extended) => id
    .toRadixString(16)
    .toUpperCase()
    .padLeft(extended ? 8 : 3, '0');

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Center(
      child: Text(text, style: const TextStyle(color: Colors.grey)));
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  final TraceModel model;
  const _StatusBar({required this.model});

  @override
  Widget build(BuildContext context) {
    final last = model.statusLog.isEmpty ? '' : model.statusLog.last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _stat('Frames', '${model.totalFrames}'),
          _stat('Rate', '${model.framesPerSecond.round()} /s'),
          _stat('Bus load', '${model.busLoadPercent.toStringAsFixed(1)} %'),
          _stat('IDs', '${model.groupedRows.length}'),
          if (model.dbcPath != null)
            _stat('DBC', model.dbcPath!),
          if (model.paused)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text('PAUSED',
                  style: TextStyle(
                      color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
            ),
          Expanded(
            child: Text(last,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Row(children: [
          Text('$label ',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: _mono.copyWith(fontSize: 12)),
        ]),
      );
}

// ---------------------------------------------------------------------------

class _SendDialog extends StatefulWidget {
  final _TracerPageState state;
  const _SendDialog({required this.state});
  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  final idCtrl = TextEditingController(text: '123');
  final dataCtrl = TextEditingController(text: '00 11 22 33');
  bool extended = false;
  bool rtr = false;
  String? error;

  /// ponytail: raw hex entry only. Signal-level composing would reuse
  /// DbcSignal.rawInto, which is already written and tested.
  Future<void> _send() async {
    final id = int.tryParse(idCtrl.text.trim(), radix: 16);
    if (id == null) return setState(() => error = 'ID must be hex');
    if (id > (extended ? 0x1FFFFFFF : 0x7FF)) {
      return setState(() => error = 'ID does not fit in an ${extended ? 29 : 11}-bit identifier');
    }
    final hex = dataCtrl.text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.length.isOdd) return setState(() => error = 'Data needs whole bytes');
    if (hex.length > 16) return setState(() => error = 'Max 8 data bytes');
    final data = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < data.length; i++) {
      data[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    try {
      final frame = CanFrame(
          id: id, data: data, extended: extended, rtr: rtr,
          direction: FrameDirection.tx);
      await widget.state.bus!.send(frame);
      // Drivers that do not echo transmissions still need the frame traced.
      if (widget.state.device?.backend != 'virtual') widget.state.model.add(frame);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send CAN frame'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idCtrl,
              style: _mono,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]'))],
              decoration: const InputDecoration(
                  labelText: 'Identifier (hex)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dataCtrl,
              style: _mono,
              decoration: const InputDecoration(
                  labelText: 'Data (hex bytes)',
                  hintText: 'DE AD BE EF',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('29-bit', style: TextStyle(fontSize: 13)),
                  value: extended,
                  onChanged: (v) => setState(() => extended = v!),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('RTR', style: TextStyle(fontSize: 13)),
                  value: rtr,
                  onChanged: (v) => setState(() => rtr = v!),
                ),
              ),
            ]),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _send, child: const Text('Send')),
      ],
    );
  }
}
