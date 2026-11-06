@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tu_expense_tracker/src/mobile/screens/report_bug_dialog.dart';
import 'package:tu_expense_tracker/src/mobile/screens/settings_screen.dart';
import 'package:tu_expense_tracker/src/mobile/services/github_contribution_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'TU Expense Tracker',
    packageName: 'com.tu.expense.manager',
    version: '2.8.2',
    buildNumber: '49',
    buildSignature: '',
  );

  String? mockClipboardText;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    mockClipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        mockClipboardText = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': mockClipboardText};
      }
      return null;
    });
  });

  group('GitHubContributionHelper bug reporting methods', () {
    test('generateBugReportBody formats description, steps, and diagnostics', () {
      const diag = DeviceDiagnostics(
        appVersion: '2.8.2',
        appBuild: '49',
        deviceModel: 'Pixel 8',
        osVersion: '14',
        sdkInt: 34,
      );

      final body = GitHubContributionHelper.generateBugReportBody(
        description: 'App freezes on first launch.',
        stepsToReproduce: '1. Open app\n2. Wait 2 seconds',
        diagnostics: diag,
      );

      expect(body, contains('### 🐛 Bug Report'));
      expect(body, contains('#### Description\nApp freezes on first launch.'));
      expect(body, contains('#### Steps to Reproduce\n1. Open app\n2. Wait 2 seconds'));
      expect(body, contains('- **App Version**: 2.8.2 (build 49)'));
      expect(body, contains('- **Device**: Pixel 8'));
      expect(body, contains('- **OS**: Android 14 (API 34)'));
      expect(body, contains('Reported voluntarily via TU Expense Tracker.'));
    });

    test('generateBugReportBody omits steps when empty', () {
      const diag = DeviceDiagnostics(
        appVersion: '2.8.2',
        appBuild: '',
        deviceModel: 'Generic Device',
        osVersion: '13',
      );

      final body = GitHubContributionHelper.generateBugReportBody(
        description: 'Minor UI glitch in categories',
        diagnostics: diag,
      );

      expect(body, isNot(contains('#### Steps to Reproduce')));
      expect(body, contains('#### Description\nMinor UI glitch in categories'));
      expect(body, contains('- **App Version**: 2.8.2'));
      expect(body, contains('- **Device**: Generic Device'));
    });

    test('buildBugReportUri formats title with prefix and labels=bug', () {
      final uri = GitHubContributionHelper.buildBugReportUri(
        title: 'Crash in settings',
        body: 'Bug details',
      );

      expect(uri.host, 'github.com');
      expect(uri.path, '/${GitHubContributionHelper.repoOwner}/${GitHubContributionHelper.repoName}/issues/new');
      expect(uri.queryParameters['title'], '[Bug Report]: Crash in settings');
      expect(uri.queryParameters['body'], 'Bug details');
      expect(uri.queryParameters['labels'], 'bug');
    });

    test('buildBugReportUri preserves existing [Bug Report] prefix', () {
      final uri = GitHubContributionHelper.buildBugReportUri(
        title: '[Bug Report]: Transaction button missing',
        body: 'Details',
      );

      expect(uri.queryParameters['title'], '[Bug Report]: Transaction button missing');
    });

    test('fetchDeviceDiagnostics parses native channel getDeviceInfo response', () async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.tu.expense.manager/telephony'),
        (MethodCall call) async {
          if (call.method == 'getDeviceInfo') {
            return <String, Object?>{
              'manufacturer': 'Google',
              'model': 'Pixel 8',
              'androidVersion': '14',
              'sdkInt': 34,
            };
          }
          return null;
        },
      );

      final diag = await GitHubContributionHelper.fetchDeviceDiagnostics(
        appVersion: '2.8.2',
        appBuild: '49',
      );

      expect(diag.appVersion, '2.8.2');
      expect(diag.appBuild, '49');
      expect(diag.summary, contains('2.8.2'));
    });
  });

  group('ReportBugDialog UI', () {
    testWidgets('renders dialog with diagnostics, fields, and action buttons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ReportBugDialog.show(
                  context,
                  appVersion: '2.8.2',
                  appBuild: '49',
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Report a Bug'), findsOneWidget);
      expect(find.text('System Diagnostics'), findsOneWidget);
      expect(find.text('Submit on GitHub'), findsOneWidget);
      expect(find.text('Copy Bug Report'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(3));
    });

    testWidgets('validation prevents submit when fields are empty', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ReportBugDialog.show(
                  context,
                  appVersion: '2.8.2',
                  appBuild: '49',
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap Submit on GitHub without entering title/description
      await tester.tap(find.text('Submit on GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a brief issue summary.'), findsOneWidget);

      // Enter title only
      await tester.enterText(find.widgetWithText(TextField, 'Issue Summary *'), 'Crash on startup');
      await tester.tap(find.text('Submit on GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('Please describe the issue or bug.'), findsOneWidget);
    });

    testWidgets('Copy Bug Report copies formatted text to clipboard', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ReportBugDialog.show(
                  context,
                  appVersion: '2.8.2',
                  appBuild: '49',
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Issue Summary *'), 'Button alignment issue');
      await tester.enterText(find.widgetWithText(TextField, 'Description *'), 'The save button is slightly off-center.');
      await tester.enterText(find.widgetWithText(TextField, 'Steps to Reproduce (Optional)'), '1. Go to settings');

      await tester.tap(find.text('Copy Bug Report'));
      await tester.pumpAndSettle();

      expect(find.text('Bug report copied to clipboard!'), findsOneWidget);
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData?.text, contains('Button alignment issue'));
      expect(clipboardData?.text, contains('The save button is slightly off-center.'));
      expect(clipboardData?.text, contains('1. Go to settings'));
      expect(clipboardData?.text, contains('2.8.2'));
    });

    testWidgets('Submit on GitHub shows confirmation dialog and launches URL', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.tu.expense.manager/telephony'),
        (MethodCall call) async {
          if (call.method == 'openUrl') return true;
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ReportBugDialog.show(
                  context,
                  appVersion: '2.8.2',
                  appBuild: '49',
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Issue Summary *'), 'Crash on tap');
      await tester.enterText(find.widgetWithText(TextField, 'Description *'), 'App closes unexpectedly.');

      // Tap Submit on GitHub
      await tester.tap(find.text('Submit on GitHub'));
      await tester.pumpAndSettle();

      // Confirmation dialog should be displayed
      expect(find.text('Post publicly on GitHub?'), findsOneWidget);

      // Confirm
      await tester.tap(find.text('Open GitHub'));
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Report a Bug'), findsNothing);
    });
  });

  group('SettingsScreen bug reporting option', () {
    testWidgets('SettingsScreen has Report a bug as the first option', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
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

      expect(find.text('Support & Feedback'), findsOneWidget);
      expect(find.text('Report a bug'), findsOneWidget);
      expect(
        find.text('Found an issue? Send diagnostics and submit a bug report on GitHub.'),
        findsOneWidget,
      );

      // Tap on Report a bug
      await tester.tap(find.text('Report a bug'));
      await tester.pumpAndSettle();

      // ReportBugDialog appears
      expect(find.text('Report a Bug'), findsOneWidget);
      expect(find.text('Submit on GitHub'), findsOneWidget);
    });
  });
}
