import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/admin/data/import_repository.dart';
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/domain/finance_models.dart';
import 'package:smartems/features/finance/domain/money.dart';
import 'package:smartems/features/setup/data/setup_repository.dart';

void main() {
  final path = Platform.environment['EMS_ASYNC_FIXTURE'];
  test(
    'real repositories queue and complete import, invoices and timetable',
    () async {
      final fixture =
          jsonDecode(File(path!).readAsStringSync()) as Map<String, dynamic>;
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:8080',
          headers: {'Authorization': 'Bearer ${fixture['token']}'},
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final imports = ImportRepository(dio);
      final finance = FinanceRepository(dio);
      final setup = SetupRepository(dio);
      Future<Map<String, dynamic>> finish(
        Future<Map<String, dynamic>> Function() read,
      ) async {
        for (int i = 0; i < 60; i++) {
          final job = await read();
          if (job['status'] == 'completed') return job;
          if (job['status'] == 'failed' || job['status'] == 'closed') {
            fail('Job stopped: ${job['error_code']}');
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        fail('Job did not complete within bounded test wait');
      }

      try {
        final upload = await imports.importStudents(
          'first_name,last_name,admission_number,class_name,section_name\nFixture,Student,ASYNC-1,Async Class,A\n',
        );
        expect(upload.status, 'pending');
        expect(upload.successRows, 0);
        final imported = await finish(
          () => imports.loadStatus(upload.jobId, CancelToken()),
        );
        expect(imported['successRows'], 1);
        expect(imported['errorRows'], 0);
        final head = await finance.createHead(
          name: 'Fixture tuition',
          isRecurring: true,
        );
        final plan = await finance.createPlan(
          name: 'Fixture plan',
          frequency: 'monthly',
          classId: fixture['classId'],
          academicYearId: fixture['yearId'],
          campusId: fixture['campusId'],
          dueDay: 10,
          graceDays: 0,
          items: [(feeHeadId: head.id, amount: Money.tryParse('100.00')!)],
        );
        final queued = await finance.generate(
          planId: plan.id,
          period: '2026-10',
        );
        expect(queued.pending, isTrue);
        final billed = await finish(
          () => finance.loadWorkflow(queued.jobId!, CancelToken()),
        );
        final counts = GenerationResult.fromJson(
          (billed['result'] as Map).cast<String, dynamic>(),
        );
        expect(counts.generated, 1);
        expect(counts.skipped, 0);
        final repeat = await finance.generate(
          planId: plan.id,
          period: '2026-10',
        );
        final repeated = await finish(
          () => finance.loadWorkflow(repeat.jobId!, CancelToken()),
        );
        expect((repeated['result'] as Map)['generated'], 0);
        expect((repeated['result'] as Map)['skipped'], 1);
        final timetable = await setup.generateTimetable({
          'campusId': fixture['campusId'],
          'academicYearId': fixture['yearId'],
          'clearExisting': false,
          'sections': [
            {
              'sectionId': fixture['sectionId'],
              'subjects': [
                {
                  'subjectId': fixture['subjectId'],
                  'preferredTeacherId': fixture['staffId'],
                  'periodsPerWeek': 1,
                },
              ],
            },
          ],
        });
        expect(timetable['status'], 'pending');
        final generated = await finish(
          () => setup.loadWorkflow(timetable['jobId'], CancelToken()),
        );
        expect((generated['result'] as Map)['applied'], isTrue);
        expect(
          (await setup.loadWeek(
            sectionId: fixture['sectionId'],
            academicYearId: fixture['yearId'],
          )).length,
          1,
        );
      } finally {
        dio.close(force: true);
      }
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
