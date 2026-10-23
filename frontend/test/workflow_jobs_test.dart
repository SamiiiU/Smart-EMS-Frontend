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
      expect(find.textContaining('pending'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      dio.close();
    },
  );
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
