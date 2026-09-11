# CANtracer

An open-source, cross-platform CAN bus tracer with DBC decoding. The 10 % of
CANoe most people actually use: watch the bus, name the messages, read the
signals, poke a frame back.

Windows · macOS · Linux — one Flutter codebase, no native plugin code.

## Features

- **Grouped view** — one row per identifier with count, cycle time and
  per-byte change highlighting (the CANoe "fixed" trace)
- **Live view** — scrolling frame-by-frame log, newest first
- **DBC decoding** — load a `.dbc`, messages get names and an expander; open
  one and its signals appear inline beneath it, scaled with units, value
  tables and multiplexing resolved — the CANoe trace window layout
- **Filtering** — hex id list/ranges (`100, 200-2FF`) and "DBC only"
- **Send** — raw frames, 11/29-bit, RTR
- **Export** — CSV of the trace buffer
- **Stats** — frames/s and approximate bus load

## Supported hardware

| Backend | Devices | OS | How it's bound |
|---|---|---|---|
| SLCAN | CANable, CANtact, USBtin, Lawicel CAN232, most cheap USB-CAN sticks | all | libserialport, bundled |
| SocketCAN | any Linux kernel CAN driver, `vcan`, gs_usb, PEAK, Kvaser… | Linux | `dart:ffi` → libc |
| PCAN | PCAN-USB, -PCI, -LAN | all | `dart:ffi` → `PCANBasic.dll` / `libpcanbasic.so` / `libPCBUSB.dylib` |
| Vector XL | VN1610/1630, CANcaseXL, VN8900… | Windows | `dart:ffi` → `vxlapi64.dll` |
| Virtual | demo generator, loopback | all | — |

Vendor backends bind to the driver the vendor already installs — nothing to
compile. If a driver library isn't found the backend simply doesn't list
devices; the status line tells you what to install.

### Driver notes

- **PCAN Windows/Linux**: install the PEAK driver package; it ships PCANBasic.
- **PCAN macOS**: install [MacCAN PCBUSB](https://mac-can.github.io/) —
  it exposes the PCANBasic API as `libPCBUSB.dylib`.
- **Vector**: install the XL Driver Library and assign channels in
  *Vector Hardware Config*. CANtracer lists application-channel indices 0-7;
  pick the one you assigned.
- **SocketCAN**: if the link is down CANtracer runs
  `ip link set canX up type can bitrate N`, which needs root. Either run that
  yourself first or start the app with `sudo`.
- **SLCAN**: only ports that answer the `V` version query with SLCAN framing
  (bare CR, or a BEL) are listed, plus anything whose USB descriptor names a
  known adapter (CANable, CANtact, USBtin…). Bluetooth and debug consoles are
  never probed. Toggle **All ports** to list every serial port if your
  adapter's firmware doesn't answer `V`. Bitrates come from the fixed
  S0–S8 table (10k–1M).

## Building

```sh
make test     # 102 tests, no hardware needed
make run      # picks macos / linux / windows from the host; override with OS=
make build    # release bundle into build/<os>/
```

Linux additionally needs `ninja-build libgtk-3-dev`. Release builds land in
`build/<os>/…`; CI produces them for all three platforms on every push.

Try it without hardware: choose **Demo traffic generator**, Connect, then
**Load DBC** → `example/demo.dbc`.

## Architecture

```
lib/src/can.dart          CanFrame, CanBus, CanBackend — the whole contract
lib/src/dbc.dart          DBC parser + bit-exact signal extraction/insertion
lib/src/trace.dart        ring buffer, per-id rows, stats, 20 Hz repaint tick
lib/src/backends/*.dart   one file per device family
lib/src/registry.dart     the list of backends; add one line to add a family
lib/main.dart             the UI
```

Every backend splits into a **pure codec** (bytes/strings ⇄ `CanFrame`, unit
tested) and a thin **transport** (FFI or serial, untestable without a device).
The struct layouts for PCAN, SocketCAN and Vector are pinned by tests, so a
transport bug is confined to the handful of driver calls.

Received frames never touch the widget tree directly: `TraceModel.add` does
bookkeeping only and a fixed 50 ms timer repaints. That is what keeps the UI
responsive at a saturated 1 Mbit/s bus.

## Not (yet) here

CAN FD, signal-level transmit composer, logging to disk beyond CSV, graphing.
`DbcSignal.rawInto` already exists and is tested, so a signal-based send dialog
is a UI-only addition. Search the code for `ponytail:` to find every
deliberate simplification and its upgrade path.

## License

MIT
