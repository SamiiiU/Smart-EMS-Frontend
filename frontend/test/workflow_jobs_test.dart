import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/features/admin/presentation/workflow_jobs_screen.dart';

class JobsAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String status = 'failed';
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<List<int>>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(request);
    dynamic body;
    final row = {
      'id': '01900000-0000-7000-8000-000000000001',
      'kind': 'INVOICES',
      'status': status,
      'failure_limit': 3,
      'error_code': status == 'failed' ? 'processing_failed' : null,
      'result': {'generated': 2, 'skipped': 1, 'total': 3},
    };
    if (request.method == 'POST') {
      status = 'pending';
      body = {'status': 'pending'};
    } else if (request.path.endsWith('/history')) {
      body = [];
    } else if (request.path == '/api/workflow-jobs') {
      body = [row];
    } else {
      body = row;
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _InputChanged extends JobsAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<List<int>>? stream, Future<void>? cancel) async {
    final r = await super.fetch(request, stream, cancel);
    final text = await utf8.decodeStream(r.stream);
    return ResponseBody.fromString(text.replaceAll('processing_failed', 'input_changed'), 200,
        headers: {'content-type': ['application/json']});
  }
}

void main() {
  setUpAll(() async {
    for (final name in ['PlusJakartaSans', 'Roboto']) {
      final fonts = FontLoader(name)
        ..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
      await fonts.load();
    }
  });
  testWidgets(
    'server-backed history reappears after remount and retry is audited/idempotent',
    (tester) async {
      final adapter = JobsAdapter(),
          dio = Dio()..httpClientAdapter = JobsAdapter();
      dio.httpClientAdapter = adapter;
      Widget screen() => MaterialApp(
        theme: AppTheme.light(role: AppRole.admin),
        home: WorkflowJobsScreen(dio: dio),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.textContaining('INVOICES'), findsOneWidget);
      await tester.tap(find.textContaining('INVOICES'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry reviewed job'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Provider configuration reviewed',
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      final actions = adapter.requests
          .where((request) => request.method == 'POST')
          .toList();
      expect(actions, hasLength(1));
      expect(
        actions.single.headers['Idempotency-Key'],
        matches(RegExp(r'^[0-9a-f-]{36}$')),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.textContaining('Pending'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      dio.close();
    },
  );
  testWidgets('short recovery reason shows an error and sends nothing', (tester) async {
    final adapter = JobsAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(role: AppRole.admin), home: WorkflowJobsScreen(dio: dio)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('INVOICES'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice generation: Failed'), findsNWidgets(2)); // detail heading + list row
    await tester.tap(find.text('Retry reviewed job'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ok');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Enter at least 5 characters.'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    dio.close();
  });
  testWidgets('keyboard: Tab to a job, Enter opens detail with focus, Close details restores focus, Space reopens', (tester) async {
    final adapter = JobsAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(role: AppRole.admin), home: WorkflowJobsScreen(dio: dio)));
    await tester.pumpAndSettle();
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    for (var i = 0; i < 12 && !(focused() ?? '').startsWith('job-0190'); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focused(), 'job-01900000-0000-7000-8000-000000000001');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Close details'), findsOneWidget);
    expect(focused(), 'job-detail');
    await tester.ensureVisible(find.text('Close details'));
    await tester.tap(find.text('Close details'));
    await tester.pumpAndSettle();
    expect(find.text('Close details'), findsNothing);
    expect(focused(), 'job-01900000-0000-7000-8000-000000000001');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Close details'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    dio.close();
  });
  testWidgets('input_changed: retry disabled with the explanation; close still offered', (tester) async {
    final adapter = _InputChanged();
    final dio = Dio()..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(role: AppRole.admin), home: WorkflowJobsScreen(dio: dio)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('INVOICES'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Retry is unavailable because'), findsOneWidget);
    final retry = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Retry reviewed job'));
    expect(retry.onPressed, isNull);
    expect(find.text('Close job'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    dio.close();
  });
  testWidgets(
    'job history renders at phone and desktop widths without overflow',
    (tester) async {
      final directory = Platform.environment['EMS_VISUAL_DIR'];
      for (final width in [360.0, 1280.0]) {
        await tester.binding.setSurfaceSize(Size(width, 800));
        final dio = Dio()..httpClientAdapter = JobsAdapter();
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(role: AppRole.admin),
            home: RepaintBoundary(
              key: key,
              child: WorkflowJobsScreen(dio: dio),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (directory != null) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$directory/jobs-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        dio.close();
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
}
