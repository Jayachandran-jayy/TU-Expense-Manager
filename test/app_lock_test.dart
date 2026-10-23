// VM only: App lock is an Android feature: it uses local_auth and the mobile settings screen.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tu_expense_tracker/src/core/ledger_prefs.dart';
import 'package:tu_expense_tracker/src/mobile/screens/app_lock_screen.dart';
import 'package:tu_expense_tracker/src/mobile/screens/settings_screen.dart';
import 'package:tu_expense_tracker/src/mobile/services/app_lock_service.dart';
import 'package:tu_expense_tracker/src/mobile/widgets/app_lock_wrapper.dart';

class FakeLocalAuthentication extends LocalAuthentication {
  bool canAuthenticateWithBiometrics = true;
  bool isSupported = true;
  bool authResult = true;
  int authCallCount = 0;

  @override
  Future<bool> get canCheckBiometrics async => canAuthenticateWithBiometrics;

  @override
  Future<bool> isDeviceSupported() async => isSupported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<dynamic> authMessages = const <dynamic>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authCallCount++;
    return authResult;
  }
}

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

  group('LedgerPrefs App Lock', () {
    test('appLockEnabled defaults to false and persists updates', () async {
      final LedgerPrefs prefs = LedgerPrefs.instance;
      expect(await prefs.appLockEnabled(), isFalse);

      await prefs.setAppLockEnabled(true);
      expect(await prefs.appLockEnabled(), isTrue);

      await prefs.setAppLockEnabled(false);
      expect(await prefs.appLockEnabled(), isFalse);
    });
  });

  group('AppLockService', () {
    late FakeLocalAuthentication fakeAuth;
    late AppLockService service;

    setUp(() {
      fakeAuth = FakeLocalAuthentication();
      service = AppLockService(auth: fakeAuth);
    });

    test('canAuthenticate returns true when supported', () async {
      expect(await service.canAuthenticate(), isTrue);

      fakeAuth.canAuthenticateWithBiometrics = false;
      fakeAuth.isSupported = false;
      expect(await service.canAuthenticate(), isFalse);
    });

    test('authenticate calls localAuth and unlocks on success', () async {
      service.isLocked.value = true;
      fakeAuth.authResult = true;

      final bool result = await service.authenticate();
      expect(result, isTrue);
      expect(service.isLocked.value, isFalse);
      expect(fakeAuth.authCallCount, 1);
    });

    test('authenticate leaves locked on failure', () async {
      service.isLocked.value = true;
      fakeAuth.authResult = false;

      final bool result = await service.authenticate();
      expect(result, isFalse);
      expect(service.isLocked.value, isTrue);
    });

    test('checkAndLock only locks when preference is enabled', () async {
      final LedgerPrefs prefs = LedgerPrefs.instance;
      await prefs.setAppLockEnabled(false);
      service.isLocked.value = false;

      await service.checkAndLock();
      expect(service.isLocked.value, isFalse);

      await prefs.setAppLockEnabled(true);
      await service.checkAndLock();
      expect(service.isLocked.value, isTrue);
    });
  });

  group('AppLockScreen Widget', () {
    testWidgets('renders lock message and unlock button', (WidgetTester tester) async {
      final FakeLocalAuthentication fakeAuth = FakeLocalAuthentication();
      fakeAuth.authResult = false; // keep on screen
      final AppLockService service = AppLockService(auth: fakeAuth);
      service.isLocked.value = true;

      bool unlockedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AppLockScreen(
            service: service,
            onUnlocked: () => unlockedCalled = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('TU Expense Tracker'), findsOneWidget);
      expect(
        find.text('App is locked to protect your financial data.'),
        findsOneWidget,
      );
      expect(find.text('Unlock with Biometrics / PIN'), findsOneWidget);

      // Tap the unlock button with auth succeeding
      fakeAuth.authResult = true;
      await tester.tap(find.text('Unlock with Biometrics / PIN'));
      await tester.pumpAndSettle();

      expect(unlockedCalled, isTrue);
    });
  });

  group('AppLockWrapper Widget', () {
    testWidgets('shows child when unlocked, AppLockScreen when locked',
        (WidgetTester tester) async {
      final FakeLocalAuthentication fakeAuth = FakeLocalAuthentication();
      fakeAuth.authResult = false;
      final AppLockService service = AppLockService(auth: fakeAuth);
      service.isLocked.value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AppLockWrapper(
            service: service,
            child: const Text('Sensitive Financial Ledger Content'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sensitive Financial Ledger Content'), findsOneWidget);
      expect(find.text('Unlock with Biometrics / PIN'), findsNothing);

      // Lock the service
      service.isLocked.value = true;
      await tester.pump();

      expect(find.text('Sensitive Financial Ledger Content'), findsNothing);
      expect(find.text('Unlock with Biometrics / PIN'), findsOneWidget);

      // Unlock
      service.unlock();
      await tester.pump();

      expect(find.text('Sensitive Financial Ledger Content'), findsOneWidget);
    });

    testWidgets('locks on paused lifecycle when enabled and not authenticating',
        (WidgetTester tester) async {
      final LedgerPrefs prefs = LedgerPrefs.instance;
      await prefs.setAppLockEnabled(true);

      final FakeLocalAuthentication fakeAuth = FakeLocalAuthentication();
      final AppLockService service = AppLockService(auth: fakeAuth);
      service.isLocked.value = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AppLockWrapper(
            service: service,
            child: const Text('Sensitive Content'),
          ),
        ),
      );
      await tester.pump();

      // Inactive should NOT lock
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(service.isLocked.value, isFalse);

      // Paused should lock
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(service.isLocked.value, isTrue);
    });
  });

  group('SettingsScreen App Lock Switch', () {
    testWidgets('displays App lock switch in Preferences',
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

      expect(find.text('App lock'), findsOneWidget);
      expect(
        find.text(
          'Require fingerprint, face, or device screen lock to open the app. Off by default.',
        ),
        findsOneWidget,
      );
    });
  });
}
