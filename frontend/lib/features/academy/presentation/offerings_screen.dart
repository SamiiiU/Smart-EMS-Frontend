import 'package:flutter/material.dart';

import '../../../core/theme/scales.dart';
import '../../../core/widgets/adaptive_data_view.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/inline_alert.dart';
import '../data/academy_repository.dart';
import '../domain/academy_models.dart';
import 'academy_common.dart';

/// Course offerings: a catalogue course running at ONE campus within one
/// academic session. Lists follow the campus switcher; creating one needs an
/// explicitly chosen campus where this account holds academy.manage.
class OfferingsScreen extends StatefulWidget {
  const OfferingsScreen({required this.repository, super.key});
  final AcademyRepository repository;

  @override
  State<OfferingsScreen> createState() => _OfferingsScreenState();
}

class _OfferingsScreenState extends State<OfferingsScreen> {
  final _loader = GlobalKey<AcademyLoaderState<List<Offering>>>();

  Future<void> _create(String campusId) async {
    final loaded = await loadForForm(
      context,
      () async => (
        courses: await widget.repository.courses(),
        years: await widget.repository.academicYears(campusId),
      ),
    );
    if (loaded == null || !mounted) return;
    final courses = loaded.courses.where((c) => !c.archived).toList();
    final years = loaded.years;
    if (courses.isEmpty || years.isEmpty) {
      return showResult(
        context,
        courses.isEmpty
            ? 'Add a course first.'
            : 'This campus has no academic session yet (Setup → Academic years).',
        error: true,
      );
    }
    String? courseId, yearId;
    var name = '', start = isoDate(DateTime.now()), end = '', status = 'open';
    final saved = await showFormDialog(
      context,
      title: 'Offer a course at ${campusName(context, campusId)}',
      submitLabel: 'Create offering',
      canSubmit: () =>
          courseId != null &&
          yearId != null &&
          name.trim().isNotEmpty &&
          isDate(start) &&
          isDate(end),
      fields: (context, setState) => Column(
        children: [
          dropdown<String>('Course', courseId, [
            for (final c in courses) (c.id, '${c.code} · ${c.name}'),
          ], (v) => setState(() => courseId = v)),
          dropdown<String>('Academic session', yearId, [
            for (final y in years) (y.id, y.label),
          ], (v) => setState(() => yearId = v)),
          field(
            'Offering name',
            name,
            (v) => setState(() => name = v),
            placeholder: 'e.g. Mathematics 2026–27',
            required: true,
          ),
          field(
            'Start date',
            start,
            (v) => setState(() => start = v),
            placeholder: 'YYYY-MM-DD',
            required: true,
            error: start.isEmpty || isDate(start) ? null : 'Use YYYY-MM-DD.',
          ),
          field(
            'End date',
            end,
            (v) => setState(() => end = v),
            placeholder: 'YYYY-MM-DD',
            required: true,
            error: end.isEmpty || isDate(end) ? null : 'Use YYYY-MM-DD.',
          ),
          dropdown<String>('Status', status, const [
            ('open', 'Open'),
            ('planned', 'Planned'),
          ], (v) => setState(() => status = v ?? 'open')),
        ],
      ),
      submit: () => attempt(
        () => widget.repository.createOffering(
          courseId: courseId!,
          campusId: campusId,
          academicYearId: yearId!,
          name: name.trim(),
          startDate: start.trim(),
          endDate: end.trim(),
          status: status,
        ),
      ),
    );
    if (saved) await _loader.currentState?.reload();
  }

  Future<void> _setStatus(Offering o, String status) async {
    if (status == 'cancelled' &&
        !await confirmAction(
          context,
          title: 'Cancel ${o.name}?',
          message: 'A cancelled offering takes no new batches.',
          confirmLabel: 'Cancel offering',
        )) {
      return;
    }
    final message = await attempt(
      () => widget.repository.setOfferingStatus(o.id, status),
    );
    if (!mounted) return;
    if (message != null) return showResult(context, message, error: true);
    await _loader.currentState?.reload();
  }

  final _reload = CampusReload();

  @override
  Widget build(BuildContext context) {
    final campus = mutationCampus(context, academyManage);
    final filter = listCampus(context, academyManage);
    _reload.track(filter, _loader);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: campus == null
              ? const InlineAlert(
                  tone: InlineAlertTone.info,
                  message:
                      'Choose a campus in More → Campus to offer a course there.',
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: 'Offer a course at ${campusName(context, campus)}',
                    icon: Icons.add,
                    onPressed: () => _create(campus),
                  ),
                ),
        ),
        Expanded(
          child: AcademyLoader<List<Offering>>(
            key: _loader,
            // The selected campus narrows the list; "All Campuses" lists every managed campus.
            load: () => widget.repository.offerings(campusId: filter),
            isEmpty: (v) => v.isEmpty,
            emptyTitle: 'No offerings',
            emptyMessage:
                'Offer a catalogue course at a campus to start creating batches.',
            builder: (context, rows, _) => SizedBox.expand(
              child: AdaptiveDataView<Offering>(
                rows: rows,
                semanticLabel: (o) => '${o.name}, ${o.courseName}, ${o.status}',
                columns: [
                  DataColumnSpec(
                    label: 'Offering',
                    value: (o) => o.name,
                    flex: 2,
                  ),
                  DataColumnSpec(label: 'Course', value: (o) => o.courseName),
                  DataColumnSpec(
                    label: 'Campus',
                    value: (o) => campusName(context, o.campusId),
                  ),
                  DataColumnSpec(
                    label: 'Dates',
                    value: (o) => '${o.startDate} → ${o.endDate}',
                  ),
                  DataColumnSpec(
                    label: 'Status',
                    value: (o) => o.status,
                    cell: (o) => StatusChip(o.status),
                  ),
                ],
                rowActions: [
                  RowAction(
                    label: 'Open',
                    onPressed: (o) => _setStatus(o, 'open'),
                    isVisible: (o) => o.status == 'planned',
                  ),
                  RowAction(
                    label: 'Close',
                    onPressed: (o) => _setStatus(o, 'closed'),
                    isVisible: (o) => o.status == 'open',
                  ),
                  RowAction(
                    label: 'Cancel',
                    onPressed: (o) => _setStatus(o, 'cancelled'),
                    isVisible: (o) => o.acceptsBatches,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
