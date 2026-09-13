import 'dart:convert';
import 'dart:io';

/// Injected at build time: `--dart-define=APP_VERSION=1.2.3` (see Makefile / CI).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');

const _repo = 'PanterSoft/Pantrace';
const releasesUrl = 'https://github.com/$_repo/releases/latest';

/// Tag of a newer GitHub release, or null when up to date.
/// Throws when the check could not run (offline, rate-limited, private repo),
/// so a user-triggered check can say so instead of claiming "up to date".
Future<String?> checkForUpdate({String repo = _repo}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = 'Pantrace/$appVersion'; // GitHub 403s an empty User-Agent
  try {
    final url = 'https://api.github.com/repos/$repo/releases/latest';
    final res = await (await client.getUrl(Uri.parse(url))).close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('GitHub returned ${res.statusCode}', uri: Uri.parse(url));
    }
    final tag = jsonDecode(await res.transform(utf8.decoder).join())['tag_name'] as String;
    return isNewer(tag, appVersion) ? tag : null;
  } finally {
    client.close();
  }
}

/// True if [a] is a higher `[v]MAJOR.MINOR.PATCH` than [b].
bool isNewer(String a, String b) {
  List<int> parse(String v) =>
      v.replaceFirst('v', '').split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final x = parse(a), y = parse(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// Open the releases page in the system browser.
void openReleasePage() => Process.run(
      Platform.isWindows ? 'cmd' : Platform.isMacOS ? 'open' : 'xdg-open',
      [if (Platform.isWindows) ...['/c', 'start', ''], releasesUrl],
    );

// --- installing ---------------------------------------------------------

/// Release asset this platform can install unattended, or null when it has no
/// such path (Linux: the .deb needs root, so the browser takes over).
String? get _assetName => Platform.isWindows
    ? 'Pantrace-windows-x64-setup.exe'
    : Platform.isMacOS
        ? 'Pantrace-macos.dmg'
        : null;

bool get canSelfInstall => _assetName != null;

String assetUrl(String tag, {String repo = _repo}) =>
    'https://github.com/$repo/releases/download/$tag/$_assetName';

/// Download the [tag] release and hand it to the OS installer, then quit so the
/// files being replaced are not in use. Never returns on success. Throws
/// otherwise, leaving the running install untouched.
Future<Never> downloadAndInstall(String tag,
    {void Function(double)? onProgress, String repo = _repo}) async {
  final file = File('${Directory.systemTemp.path}/$_assetName');
  await _download(assetUrl(tag, repo: repo), file, onProgress);
  if (Platform.isWindows) {
    // Inno Setup: silent, closes and relaunches us around the file swap.
    await Process.start(file.path,
        ['/SILENT', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS', '/NORESTART'],
        mode: ProcessStartMode.detached);
  } else {
    // ponytail: a detached shell swaps the bundle once we are gone — the
    // signed-and-notarised route is Sparkle, which needs signing infra we lack.
    final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
    await Process.start(
        '/bin/sh',
        [
          '-c',
          'sleep 2; m=\$(mktemp -d); '
              'hdiutil attach -nobrowse -quiet ${_q(file.path)} -mountpoint "\$m" && '
              'rm -rf ${_q(app)} && cp -R "\$m/Pantrace.app" ${_q(File(app).parent.path)}; '
              'hdiutil detach -quiet "\$m"; open ${_q(app)}'
        ],
        mode: ProcessStartMode.detached);
  }
  exit(0);
}

/// Single-quote a path for /bin/sh.
String _q(String s) => "'${s.replaceAll("'", r"'\''")}'";

Future<void> _download(String url, File out, void Function(double)? onProgress) async {
  final client = HttpClient()..userAgent = 'Pantrace/$appVersion';
  try {
    final res = await (await client.getUrl(Uri.parse(url))).close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('download failed (${res.statusCode})', uri: Uri.parse(url));
    }
    final total = res.contentLength; // -1 when the server does not say
    var got = 0;
    await res.map((chunk) {
      got += chunk.length;
      if (total > 0) onProgress?.call(got / total);
      return chunk;
    }).pipe(out.openWrite());
  } finally {
    client.close();
  }
}
