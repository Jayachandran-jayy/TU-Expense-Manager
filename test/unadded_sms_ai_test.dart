// VM only: Drives the mobile settings screen and the on-device AI model, which is Android-only.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tu_expense_tracker/src/core/ledger_prefs.dart';
import 'package:tu_expense_tracker/src/mobile/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'TU Expense Tracker',
    packageName: 'com.tu.expense.manager',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('SettingsScreen displays On-device AI fallback switch and download buttons',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('On-device AI fallback'), findsOneWidget);
    expect(find.text('Download AI Model (~397 MB)'), findsOneWidget);
    expect(find.text('Select .gguf file'), findsOneWidget);

    // Tapping the switch when model is not downloaded shows download dialog
    await tester.tap(find.text('On-device AI fallback'));
    await tester.pumpAndSettle();

    expect(find.text('Download AI Model?'), findsOneWidget);
    expect(find.text('Download Now'), findsOneWidget);

    // Dismiss dialog
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Download AI Model?'), findsNothing);
  });

  test('LedgerPrefs correctly stores AI fallback toggle and custom model path', () async {
    final prefs = LedgerPrefs.instance;
    expect(await prefs.aiFallbackEnabled(), isFalse);
    expect(await prefs.customModelPath(), isNull);

    await prefs.setAiFallbackEnabled(true);
    expect(await prefs.aiFallbackEnabled(), isTrue);

    await prefs.setCustomModelPath('/data/user/0/models/test.gguf');
    expect(await prefs.customModelPath(), '/data/user/0/models/test.gguf');

    await prefs.setCustomModelPath(null);
    expect(await prefs.customModelPath(), isNull);
  });
}
