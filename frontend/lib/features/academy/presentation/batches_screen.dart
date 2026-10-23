import 'package:flutter/material.dart';

import '../../../core/theme/scales.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/search_field.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';
import 'batch_detail_screen.dart';

/// Batches the caller may see: on campuses where they hold academy.manage,
/// plus batches they currently instruct ([mine] = only the latter). The
/// server decides membership of this list; nothing here widens it.
class BatchesScreen extends StatefulWidget {
  const BatchesScreen({
    required this.repository,
    this.mine = false,
    this.feesAvailable = false,
    super.key,
  });
  final AcademyRepository repository;
  final bool mine;
  final bool feesAvailable;

  @override
  State<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends State<BatchesScreen> {
  final _loader = GlobalKey<AcademyLoaderState<List<Batch>>>();
  final _reload = CampusReload();
  String _query = '';

  Future<void> _create(String campusId) async {
    final all = await loadForForm(
      context,
      () => widget.repository.offerings(campusId: campusId),
    );
    if (all == null || !mounted) return;
    final offerings = all.where((o) => o.acceptsBatches).toList();
    if (offerings.isEmpty) {
      return showResult(
        context,
        'Offer a course at this campus first (Offerings tab).',
        error: true,
      );
    }
    String? offeringId;
    var name = '', capacity = '', room = '';
    final saved = await showFormDialog(
      context,
      title: 'New batch at ${campusName(context, campusId)}',
      submitLabel: 'Create batch',
      canSubmit: () =>
          offeringId != null &&
          name.trim().isNotEmpty &&
          (capacity.isEmpty || int.tryParse(capacity) != null),
      fields: (context, setState) => Column(
        children: [
          dropdown<String>('Offering', offeringId, [
            for (final o in offerings) (o.id, '${o.courseName} · ${o.name}'),
          ], (v) => setState(() => offeringId = v)),
          field(
            'Batch name',
            name,
            (v) => setState(() => name = v),
            placeholder: 'e.g. Evening A',
            required: true,
          ),
          field(
            'Capacity (optional)',
            capacity,
            (v) => setState(() => capacity = v),
            placeholder: '1–1000',
            error:
                capacity.isEmpty ||
                    ((int.tryParse(capacity) ?? 0) >= 1 &&
                        (int.tryParse(capacity) ?? 0) <= 1000)
                ? null
                : 'A whole number 1–1000.',
          ),
          field(
            'Default room (optional)',
            room,
            (v) => setState(() => room = v),
            placeholder: 'e.g. Room 7',
          ),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.createBatch(
          offeringId: offeringId!,
          name: name.trim(),
          capacity: int.tryParse(capacity),
          defaultRoom: room.trim().isEmpty ? null : room.trim(),
        ),
      ),
    );
    if (saved) await _loader.currentState?.reload();
  }

  void _open(Batch b) => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => BatchDetailScreen(
            repository: widget.repository,
            batchId: b.id,
            feesAvailable: widget.feesAvailable,
          ),
        ),
      )
      .then((_) => _loader.currentState?.reload());

  @override
  Widget build(BuildContext context) {
    final filter = widget.mine ? null : listCampus(context, academyManage);
    _reload.track(filter, _loader);
    final campus = widget.mine ? null : mutationCampus(context, academyManage);
    final manager =
        !widget.mine && campusesWith(context, academyManage).isNotEmpty;
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
                  label: 'Search batches',
                  value: _query,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (manager && campus != null)
                AppButton(
                  label: 'New batch',
                  icon: Icons.add,
                  onPressed: () => _create(campus),
                )
              else if (manager)
                const InlineAlert(
                  tone: InlineAlertTone.info,
                  message:
                      'Choose a campus in More → Campus to create a batch.',
                ),
            ],
          ),
        ),
        Expanded(
          child: AcademyLoader<List<Batch>>(
            key: _loader,
            load: () =>
                widget.repository.batches(campusId: filter, mine: widget.mine),
            isEmpty: (v) => v.isEmpty,
            emptyTitle: widget.mine ? 'No batches assigned' : 'No batches yet',
            emptyMessage: widget.mine
                ? 'When an administrator assigns you to a batch it appears here.'
                : 'Create a batch for an offering, then enrol learners and schedule sessions.',
            emptyIcon: Icons.groups_2_outlined,
            builder: (context, all, _) {
              final q = _query.trim().toLowerCase();
              final rows = [
                for (final b in all)
                  if (q.isEmpty ||
                      '${b.courseName} ${b.name} ${b.courseCode}'
                          .toLowerCase()
                          .contains(q))
                    b,
              ];
              if (rows.isEmpty) {
                return const Center(
                  child: Text('No batch matches this search.'),
                );
              }
              return SizedBox.expand(
                child: AdaptiveDataView<Batch>(
                  rows: rows,
                  onTap: _open,
                  rowKey: (b) => ValueKey('batch-${b.id}'),
                  semanticLabel: (b) =>
                      '${b.courseName} ${b.name}, ${b.activeLearners} learners, ${b.status}',
                  columns: [
                    DataColumnSpec(
                      label: 'Course',
                      value: (b) => b.courseName,
                      flex: 2,
                    ),
                    DataColumnSpec(label: 'Batch', value: (b) => b.name),
                    DataColumnSpec(
                      label: 'Campus',
                      value: (b) => campusName(context, b.campusId),
                    ),
                    DataColumnSpec(
                      label: 'Learners',
                      numeric: true,
                      value: (b) => b.capacity == null
                          ? '${b.activeLearners}'
                          : '${b.activeLearners}/${b.capacity}',
                    ),
                    DataColumnSpec(
                      label: 'Status',
                      value: (b) => b.status,
                      cell: (b) => StatusChip(b.status),
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
