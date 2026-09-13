import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pantrace/main.dart';
import 'package:pantrace/src/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isNewer compares semver tags', () {
    expect(isNewer('v1.0.1', '1.0.0'), isTrue);
    expect(isNewer('v1.10.0', '1.9.9'), isTrue);
    expect(isNewer('2.0.0', 'v1.99.99'), isTrue);
    expect(isNewer('v1.0.0', '1.0.0'), isFalse);
    expect(isNewer('v0.9.0', '1.0.0'), isFalse);
    expect(isNewer('v1.0.0', '0.0.0'), isTrue); // unversioned dev build
  });

  testWidgets('the overflow menu offers a manual update check', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    await tester.pumpWidget(const PantraceApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Check for updates'), findsOneWidget);

    // The check is offline in tests, so it must report the failure, not silence.
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Update check failed'), findsOneWidget);
  });

  test('the install asset is one CI actually publishes', () {
    // Renaming a release asset would otherwise 404 only at install time.
    final built = File('.github/workflows/ci.yml').readAsStringSync() +
        File('windows/installer.iss').readAsStringSync();
    for (final name in ['Pantrace-windows-x64-setup', 'Pantrace-macos.dmg']) {
      expect(built, contains(name));
    }
    if (!canSelfInstall) return; // Linux: the .deb needs root, browser instead
    expect(assetUrl('v1.2.3'),
        matches(r'^https://github\.com/.+/releases/download/v1\.2\.3/Pantrace-'));
  });
}
