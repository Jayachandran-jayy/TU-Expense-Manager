import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/ui_shared/loading_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnimatedCoin', () {
    testWidgets('renders currency symbol and dimensions',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnimatedCoin(symbol: '₹', size: 64),
            ),
          ),
        ),
      );

      expect(find.text('₹'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('₹'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('₹'), findsOneWidget);
    });
  });

  group('CoinProgressBar', () {
    testWidgets('renders without overflow', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CoinProgressBar(height: 10, width: 220),
            ),
          ),
        ),
      );

      expect(find.byType(CoinProgressBar), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('renders determinate value smoothly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CoinProgressBar(height: 10, width: 220, value: 0.5),
            ),
          ),
        ),
      );

      expect(find.byType(CoinProgressBar), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('LoadingModal', () {
    testWidgets('displays message, subtitle, coin, and progress bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingModal(
              message: 'Importing SMS transactions…',
              subtitle: 'Scanning your inbox for bank alerts…',
              symbol: '₹',
            ),
          ),
        ),
      );

      expect(find.text('Importing SMS transactions…'), findsOneWidget);
      expect(find.text('Scanning your inbox for bank alerts…'), findsOneWidget);
      expect(find.byType(AnimatedCoin), findsOneWidget);
      expect(find.byType(CoinProgressBar), findsOneWidget);
    });

    testWidgets('renders correctly without subtitle',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingModal(
              message: 'Syncing…',
            ),
          ),
        ),
      );

      expect(find.text('Syncing…'), findsOneWidget);
      expect(find.byType(AnimatedCoin), findsOneWidget);
    });
  });

  group('withLoadingModal', () {
    testWidgets('shows modal during async task and dismisses upon completion',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () async {
                  await withLoadingModal<void>(
                    context: context,
                    message: 'Running operation…',
                    subtitle: 'Please wait a moment…',
                    task: () async {
                      await Future<void>.delayed(
                          const Duration(milliseconds: 200));
                    },
                  );
                },
                child: const Text('Start'),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(LoadingModal), findsNothing);

      // Tap button to start task
      await tester.tap(find.text('Start'));
      await tester.pump(); // frame to trigger dialog

      expect(find.byType(LoadingModal), findsOneWidget);
      expect(find.text('Running operation…'), findsOneWidget);
      expect(find.text('Please wait a moment…'), findsOneWidget);

      // Advance clock past task duration
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(); // dialog pop animation

      expect(find.byType(LoadingModal), findsNothing);
    });

    testWidgets('dismisses cleanly even when task throws an exception',
        (WidgetTester tester) async {
      String? caughtError;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () async {
                  try {
                    await withLoadingModal<void>(
                      context: context,
                      message: 'Faulty operation…',
                      task: () async {
                        await Future<void>.delayed(
                            const Duration(milliseconds: 100));
                        throw Exception('Network failed');
                      },
                    );
                  } catch (e) {
                    caughtError = e.toString();
                  }
                },
                child: const Text('Start Failing'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Failing'));
      await tester.pump();

      expect(find.byType(LoadingModal), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(find.byType(LoadingModal), findsNothing);
      expect(caughtError, contains('Network failed'));
    });
  });

  group('ProgressController', () {
    test('calculates progress and fires listeners on updates', () {
      final controller = ProgressController(message: 'Starting…');
      expect(controller.progress, isNull);
      expect(controller.current, 0);
      expect(controller.total, 0);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.update(total: 100, current: 25, message: 'Scanning…');
      expect(notifications, 1);
      expect(controller.progress, 0.25);
      expect(controller.current, 25);
      expect(controller.total, 100);
      expect(controller.message, 'Scanning…');

      // Redundant update does not fire listeners
      controller.update(total: 100, current: 25);
      expect(notifications, 1);
    });
  });

  group('ProgressModal', () {
    testWidgets('renders message, indeterminate bar initially, and counter when total > 0',
        (WidgetTester tester) async {
      final controller = ProgressController(
        message: 'Importing SMS transactions…',
        subtitle: 'Reading inbox messages…',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressModal(
              controller: controller,
              initialMessage: 'Importing SMS transactions…',
              initialSubtitle: 'Reading inbox messages…',
            ),
          ),
        ),
      );

      expect(find.text('Importing SMS transactions…'), findsOneWidget);
      expect(find.text('Reading inbox messages…'), findsOneWidget);
      expect(find.textContaining('SMS scanned'), findsNothing);

      // Update with message counts
      controller.update(
        current: 45,
        total: 100,
        subtitle: 'Scanning messages…',
      );
      await tester.pump();

      expect(find.text('45 / 100 SMS scanned (45%)'), findsOneWidget);
      expect(find.text('Scanning messages…'), findsOneWidget);
    });
  });

  group('withProgressModal', () {
    testWidgets('runs task, receives ProgressController, and dismisses on completion',
        (WidgetTester tester) async {
      ProgressController? taskController;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () async {
                  await withProgressModal<void>(
                    context: context,
                    message: 'Scanning…',
                    task: (progress) async {
                      taskController = progress;
                      progress.update(total: 200, current: 50);
                      await Future<void>.delayed(
                          const Duration(milliseconds: 100));
                    },
                  );
                },
                child: const Text('Start Scan'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Scan'));
      await tester.pump();

      expect(find.byType(ProgressModal), findsOneWidget);
      expect(find.text('50 / 200 SMS scanned (25%)'), findsOneWidget);
      expect(taskController, isNotNull);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(find.byType(ProgressModal), findsNothing);
    });
  });
}
