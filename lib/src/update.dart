import 'dart:convert';
import 'dart:io';

/// Injected at build time: `--dart-define=APP_VERSION=1.2.3` (see Makefile / CI).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');

const _repo = 'PanterSoft/CANtracer';
const releasesUrl = 'https://github.com/$_repo/releases/latest';

/// Tag of a newer GitHub release, or null when up to date, offline, or rate-limited.
/// Needs the repo to be public; the API 404s on a private one for anonymous callers.
Future<String?> checkForUpdate({String repo = _repo}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..userAgent = 'CANtracer/$appVersion'; // GitHub 403s an empty User-Agent
  try {
    final url = 'https://api.github.com/repos/$repo/releases/latest';
    final res = await (await client.getUrl(Uri.parse(url))).close();
    if (res.statusCode != 200) return null;
    final tag = jsonDecode(await res.transform(utf8.decoder).join())['tag_name'] as String;
    return isNewer(tag, appVersion) ? tag : null;
  } catch (_) {
    return null; // ponytail: any failure = no nag; the next launch tries again
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
