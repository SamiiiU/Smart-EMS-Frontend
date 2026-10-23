import 'package:flutter/material.dart';

import '../../../core/theme/scales.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/search_field.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';

/// Course catalogue: list, search, filter by status, create, edit, archive.
/// A catalogue course is not a running class — offerings and batches are.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({required this.repository, super.key});
  final AcademyRepository repository;

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  final _loader = GlobalKey<AcademyLoaderState<List<Course>>>();
  String _query = '';
  bool _showArchived = false;

  Future<void> _edit([Course? course]) async {
    var code = course?.code ?? '',
        name = course?.name ?? '',
        description = course?.description ?? '',
        level = course?.level ?? '';
    final saved = await showFormDialog(
      context,
      title: course == null ? 'Add a course' : 'Edit ${course.code}',
      submitLabel: course == null ? 'Add course' : 'Save',
      canSubmit: () =>
          name.trim().isNotEmpty && (course != null || code.trim().isNotEmpty),
      fields: (context, setState) => Column(
        children: [
          if (course == null)
            field(
              'Code',
              code,
              (v) => setState(() => code = v),
              placeholder: 'e.g. MATH-11',
              required: true,
              error:
                  code.isEmpty ||
                      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$').hasMatch(code)
                  ? null
                  : 'Letters, digits, - or _, up to 32 characters.',
            ),
          field(
            'Name',
            name,
            (v) => setState(() => name = v),
            placeholder: 'e.g. Mathematics',
            required: true,
          ),
          field(
            'Level (optional)',
            level,
            (v) => setState(() => level = v),
            placeholder: 'e.g. FSc Part 1',
          ),
          field(
            'Description (optional)',
            description,
            (v) => setState(() => description = v),
          ),
        ],
      ),
      submit: () => attempt(() async {
        if (course == null) {
          await widget.repository.createCourse(
            code: code.trim(),
            name: name.trim(),
            description: description.trim().isEmpty ? null : description.trim(),
            level: level.trim().isEmpty ? null : level.trim(),
          );
        } else {
          await widget.repository.updateCourse(
            course.id,
            name: name.trim(),
            description: description.trim().isEmpty ? null : description.trim(),
            level: level.trim().isEmpty ? null : level.trim(),
          );
        }
      }),
    );
    if (saved) await _loader.currentState?.reload();
  }

  Future<void> _toggleArchive(Course c) async {
    final message = await attempt(
      () => widget.repository.updateCourse(
        c.id,
        status: c.archived ? 'active' : 'archived',
      ),
    );
    if (!mounted) return;
    if (message != null) return showResult(context, message, error: true);
    await _loader.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Wrap(
            spacing: AppSpacing.space5,
            runSpacing: AppSpacing.space5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: SearchField(
                  label: 'Search courses',
                  value: _query,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              FilterChip(
                label: const Text('Show archived'),
                selected: _showArchived,
                onSelected: (v) => setState(() => _showArchived = v),
              ),
              AppButton(label: 'Add course', icon: Icons.add, onPressed: _edit),
            ],
          ),
        ),
        Expanded(
          child: AcademyLoader<List<Course>>(
            key: _loader,
            load: () => widget.repository.courses(),
            isEmpty: (v) => v.isEmpty,
            emptyTitle: 'No courses yet',
            emptyMessage:
                'Add the subjects your academy teaches, such as Mathematics or Entry Test Preparation.',
            emptyIcon: Icons.menu_book_outlined,
            builder: (context, all, _) {
              final q = _query.trim().toLowerCase();
              final rows = [
                for (final c in all)
                  if ((_showArchived || !c.archived) &&
                      (q.isEmpty ||
                          c.name.toLowerCase().contains(q) ||
                          c.code.toLowerCase().contains(q)))
                    c,
              ];
              if (rows.isEmpty) {
                return const Center(
                  child: Text('No course matches this search.'),
                );
              }
              return SizedBox.expand(
                child: AdaptiveDataView<Course>(
                  rows: rows,
                  semanticLabel: (c) => '${c.code} ${c.name}, ${c.status}',
                  columns: [
                    DataColumnSpec(label: 'Code', value: (c) => c.code),
                    DataColumnSpec(
                      label: 'Course',
                      value: (c) => c.name,
                      flex: 2,
                    ),
                    DataColumnSpec(
                      label: 'Level',
                      value: (c) => c.level ?? '—',
                    ),
                    DataColumnSpec(
                      label: 'Status',
                      value: (c) => c.status,
                      cell: (c) => StatusChip(c.status),
                    ),
                  ],
                  rowActions: [
                    RowAction(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      onPressed: _edit,
                    ),
                    RowAction(
                      label: 'Archive',
                      onPressed: _toggleArchive,
                      isVisible: (c) => !c.archived,
                    ),
                    RowAction(
                      label: 'Restore',
                      onPressed: _toggleArchive,
                      isVisible: (c) => c.archived,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
