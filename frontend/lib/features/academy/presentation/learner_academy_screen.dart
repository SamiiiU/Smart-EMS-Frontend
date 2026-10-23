import 'package:flutter/material.dart';

import '../../../core/theme/scales.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/section_card.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';

/// Personal workspace: a learner's own course memberships, session
/// attendance (last 30 days) and PUBLISHED results; a guardian chooses among
/// linked children only. The server returns only that learner's rows and
/// never drafts to these accounts.
class LearnerAcademyScreen extends StatefulWidget {
  const LearnerAcademyScreen({
    required this.repository,
    required this.isStudent,
    super.key,
  });
  final AcademyRepository repository;
  final bool isStudent;

  @override
  State<LearnerAcademyScreen> createState() => _LearnerAcademyScreenState();
}

class _LearnerAcademyScreenState extends State<LearnerAcademyScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Courses',
          subtitle: widget.isStudent
              ? 'Your batches, attendance and results'
              : 'Your child\'s batches, attendance and results',
        ),
        Expanded(
          child: AcademyLoader<List<Pick>>(
            load: () => widget.repository.myLearners(student: widget.isStudent),
            isEmpty: (v) => v.isEmpty,
            emptyTitle: 'No linked learner',
            emptyMessage:
                'Ask the institution to link your account to a learner.',
            builder: (context, learners, _) {
              final id = learners.any((l) => l.id == _selected)
                  ? _selected!
                  : learners.first.id;
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.space6),
                children: [
                  if (learners.length > 1)
                    dropdown<String>('Learner', id, [
                      for (final l in learners) (l.id, l.label),
                    ], (v) => setState(() => _selected = v)),
                  _LearnerDetail(
                    key: ValueKey(id),
                    repository: widget.repository,
                    studentId: id,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LearnerDetail extends StatelessWidget {
  const _LearnerDetail({
    required this.repository,
    required this.studentId,
    super.key,
  });
  final AcademyRepository repository;
  final String studentId;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Batches',
          child: SizedBox(
            height: 300,
            child: AcademyLoader<List<Enrollment>>(
              load: () => repository.learnerEnrollments(studentId),
              isEmpty: (v) => v.isEmpty,
              emptyTitle: 'Not enrolled in any batch',
              emptyMessage: 'Course batches appear here once enrolled.',
              builder: (context, rows, _) => SizedBox.expand(
                child: AdaptiveDataView<Enrollment>(
                  rows: rows,
                  semanticLabel: (e) =>
                      '${e.courseName} ${e.batchName}, since ${e.enrolledOn}',
                  columns: [
                    DataColumnSpec(
                      label: 'Course',
                      value: (e) => e.courseName,
                      flex: 2,
                    ),
                    DataColumnSpec(label: 'Batch', value: (e) => e.batchName),
                    DataColumnSpec(label: 'Since', value: (e) => e.enrolledOn),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        SectionCard(
          title: 'Attendance — last 30 days',
          child: SizedBox(
            height: 300,
            child: AcademyLoader<List<LearnerAttendance>>(
              load: () => repository.learnerAttendance(
                studentId,
                isoDate(now.subtract(const Duration(days: 30))),
                isoDate(now),
              ),
              isEmpty: (v) => v.isEmpty,
              emptyTitle: 'No attendance recorded',
              emptyMessage:
                  'Session attendance appears here after it is marked.',
              builder: (context, rows, _) => SizedBox.expand(
                child: AdaptiveDataView<LearnerAttendance>(
                  rows: rows,
                  semanticLabel: (a) => '${a.courseName} ${a.date} ${a.status}',
                  columns: [
                    DataColumnSpec(
                      label: 'Date',
                      value: (a) => '${a.date} ${a.start}',
                    ),
                    DataColumnSpec(
                      label: 'Course',
                      value: (a) => a.courseName,
                      flex: 2,
                    ),
                    DataColumnSpec(
                      label: 'Status',
                      value: (a) => a.status,
                      cell: (a) => StatusChip(a.status),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        SectionCard(
          title: 'Results',
          child: SizedBox(
            height: 300,
            child: AcademyLoader<List<LearnerResult>>(
              load: () => repository.learnerResults(studentId),
              isEmpty: (v) => v.isEmpty,
              emptyTitle: 'No published results',
              emptyMessage:
                  'Results appear here once the academy publishes them.',
              builder: (context, rows, _) => SizedBox.expand(
                child: AdaptiveDataView<LearnerResult>(
                  // Defence in depth: the server already returns published rows only.
                  rows: [
                    for (final r in rows)
                      if (r.status == 'published') r,
                  ],
                  semanticLabel: (r) =>
                      '${r.courseName} ${r.title}: ${r.absent ? 'absent' : '${r.marks} of ${r.maxMarks}'}',
                  columns: [
                    DataColumnSpec(
                      label: 'Course',
                      value: (r) => r.courseName,
                      flex: 2,
                    ),
                    DataColumnSpec(
                      label: 'Assessment',
                      value: (r) => r.title,
                      flex: 2,
                    ),
                    DataColumnSpec(
                      label: 'Marks',
                      numeric: true,
                      value: (r) => r.absent
                          ? 'Absent'
                          : '${r.marks ?? '—'} / ${r.maxMarks}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
