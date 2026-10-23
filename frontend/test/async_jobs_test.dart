import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart';
import 'package:smartems/core/widgets/job_progress.dart';
import 'package:smartems/features/finance/domain/finance_models.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(role: AppRole.admin),
  home: Scaffold(body: child),
);

void main() {
  test('202 generation is pending, not a completed zero-invoice result', () {
    final result = GenerationResult.fromJson({
      'jobId': 'job',
      'status': 'pending',
    });
    expect(result.pending, isTrue);
    expect(result.jobId, 'job');
  });
  testWidgets('polls pending job and reports completion exactly once', (
    tester,
  ) async {
    var calls = 0, completions = 0;
    await tester.pumpWidget(
      wrap(
        JobProgress(
          jobId: 'job',
          load: (_) async {
            calls++;
            return {
              'status': calls == 1 ? 'pending' : 'completed',
              'result': {'total': 2},
            };
          },
          onFinished: (_) => completions++,
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Queued.'), findsOneWidget);
    expect(completions, 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(completions, 1);
    await tester.pump(const Duration(seconds: 20));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'dispose cancels outstanding read and schedules no more polling',
    (tester) async {
      CancelToken? token;
      final pending = Completer<Map<String, dynamic>>();
      var calls = 0;
      await tester.pumpWidget(
        wrap(
          JobProgress(
            jobId: 'job',
            load: (value) {
              token = value;
              calls++;
              return pending.future;
            },
            onFinished: (_) => fail('Disposed job must not finish'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpWidget(const SizedBox());
      expect(token!.isCancelled, isTrue);
      pending.complete({'status': 'completed'});
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1);
    },
  );
  testWidgets(
    'status errors retain job and stop automatic retries after three failures',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        wrap(
          JobProgress(
            jobId: 'saved-job',
            load: (_) async {
              calls++;
              throw StateError('Offline');
            },
            onFinished: (_) => fail('Transport error is not terminal failure'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      expect(calls, 3);
      expect(find.textContaining('saved-job'), findsOneWidget);
      await tester.tap(find.text('Check status'));
      await tester.pump();
      expect(calls, 4);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
