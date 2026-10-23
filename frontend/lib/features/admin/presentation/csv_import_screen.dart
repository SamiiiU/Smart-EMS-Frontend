import 'dart:convert';
import '../../../core/widgets/app_text_area.dart';
import '../../../core/widgets/job_progress.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../data/import_repository.dart';
import '../domain/admin_models.dart';
import '../../../core/widgets/page_header.dart';

/// Upload a CSV, then show durable job progress and final per-row results.
class CsvImportScreen extends StatefulWidget {
  const CsvImportScreen({required this.repository, super.key});

  final ImportRepository repository;

  @override
  State<CsvImportScreen> createState() => CsvImportScreenState();
}

class CsvImportScreenState extends State<CsvImportScreen> {
  final TextEditingController _controller = TextEditingController();

  bool _submitting = false;
  String? _error;
  ImportResult? _result;
  String? _pendingJobId;
  List<ImportRowError> _rowErrors = const [];

  /// Set when the import ran but its per-row errors could not be fetched.
  /// Distinct from [_error]: the import DID happen, so telling the admin it
  /// failed would be wrong — what failed is only the explanation of which
  /// rows were rejected.
  bool _rowErrorsUnavailable = false;

  /// The name of the chosen file, so the admin can see WHICH file is loaded
  /// before importing — a silently-filled box is how the wrong roster gets
  /// imported.
  String? _pickedFileName;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reads a CSV into the paste box.
  ///
  /// `readAsBytes` rather than a path: on web there is no path to read from,
  /// and the web build is this product's primary target. It also keeps the
  /// native and web routes identical rather than branching per platform.
  Future<void> _pickFile() async {
    setState(() => _error = null);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt'],
      );
      if (file == null) return; // Cancelled — not an error.

      final bytes = await file.readAsBytes();

      setState(() {
        // utf8 with allowMalformed, because a roster exported from Excel on
        // a Pakistani school's machine is not reliably clean UTF-8, and
        // throwing on one stray byte would reject the whole file. A mangled
        // character is visible in the box; a hard failure is not actionable.
        _controller.text = utf8.decode(bytes, allowMalformed: true);
        _pickedFileName = file.name;
        _result = null;
        _rowErrors = const [];
      });
    } on Object {
      if (!mounted) return;
      setState(
        () => _error =
            'That file could not be opened. Try pasting '
            'its contents instead.',
      );
    }
  }

  Future<void> submit() async {
    final csv = _controller.text.trim();
    if (csv.isEmpty || _submitting) return;

    // The backend treats line 1 as the header no matter what it contains, so
    // a paste that starts with a data row loses that row and answers
    // "CSV has no data rows" — true, but it does not say what to do. Found
    // in manual testing 2026-09-19. Checked here, before anything is sent.
    final header = csv.split(RegExp(r'\r?\n')).first;
    final columns = header.split(',').map((c) => c.trim()).toList();
    final missing = ImportRepository.studentHeaders
        .where((h) => !columns.contains(h))
        .toList();
    if (missing.isNotEmpty) {
      setState(() {
        _result = null;
        _rowErrors = const [];
        _error =
            'The first line must be the header row: '
            '${ImportRepository.studentHeaders.join(',')}. '
            'Missing: ${missing.join(', ')}. '
            'Add the header as line 1, then your students below it.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
      _rowErrors = const [];
      _rowErrorsUnavailable = false;
    });

    try {
      final result = await widget.repository.importStudents(csv);
      if (!mounted) return;
      setState(() {
        _result = result;
        _pendingJobId = const ['pending', 'processing'].contains(result.status)
            ? result.jobId
            : null;
        _submitting = _pendingJobId != null;
      });

      if (_pendingJobId == null && result.hasErrors) {
        try {
          final errors = await widget.repository.loadErrors(result.jobId);
          if (!mounted) return;
          setState(() => _rowErrors = errors);
        } on Object {
          if (!mounted) return;
          setState(() => _rowErrorsUnavailable = true);
        }
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is LoadFailure
            ? (e.message ?? 'The import could not be run.')
            : 'The import could not be run.';
      });
    }
  }

  Future<void> _finishJob(Map<String, dynamic> job) async {
    final result = ImportResult.fromJson(job);
    setState(() {
      _result = result;
      _pendingJobId = null;
      _submitting = false;
      if (result.status != 'completed') {
        _error =
            'Import stopped. Review saved counts and row errors before importing again.';
      }
    });
    if (result.hasErrors) {
      try {
        final errors = await widget.repository.loadErrors(result.jobId);
        if (mounted) setState(() => _rowErrors = errors);
      } on Object {
        if (mounted) setState(() => _rowErrorsUnavailable = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final result = _pendingJobId == null ? _result : null;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space6),
          children: [
            const PageHeader(
              title: 'Import students',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Choose your CSV file, or paste its contents below. Either way '
              'the first line has to be the header row.',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.space5),
            const _HeaderHint(),
            const SizedBox(height: AppSpacing.space5),

            // T16: paste-only was a real blocker — no principal copies a
            // roster out of Excel by hand. The file is read into the SAME
            // text field the paste path uses, so the header guard below and
            // every existing test cover both routes rather than the file
            // path being a second, unchecked way in.
            AppButton(
              label: 'Choose a CSV file',
              icon: Icons.upload_file_outlined,
              variant: AppButtonVariant.secondary,
              fullWidth: true,
              onPressed: _submitting ? null : _pickFile,
            ),
            if (_pickedFileName != null) ...[
              const SizedBox(height: AppSpacing.space3),
              InlineAlert(
                tone: InlineAlertTone.info,
                message:
                    'Loaded “$_pickedFileName”. Check it below, then '
                    'import.',
              ),
            ],
            const SizedBox(height: AppSpacing.space5),
            _PasteBox(controller: _controller, enabled: !_submitting),
            const SizedBox(height: AppSpacing.space6),
            AppButton(
              label: _submitting ? 'Importing…' : 'Import',
              fullWidth: true,
              onPressed: _submitting ? null : submit,
            ),
            if (_pendingJobId != null) ...[
              const SizedBox(height: AppSpacing.space5),
              JobProgress(
                key: ValueKey(_pendingJobId),
                jobId: _pendingJobId!,
                load: (token) =>
                    widget.repository.loadStatus(_pendingJobId!, token),
                onFinished: _finishJob,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.space6),
              InlineAlert(tone: InlineAlertTone.danger, message: _error!),
            ],
            if (result != null) ...[
              const SizedBox(height: AppSpacing.space6),
              InlineAlert(
                tone: result.hasErrors
                    ? InlineAlertTone.warning
                    : InlineAlertTone.success,
                message:
                    '${result.successRows} of ${result.totalRows} rows '
                    'imported'
                    '${result.hasErrors ? ' · ${result.errorRows} rejected' : '.'}',
              ),
              if (_rowErrorsUnavailable) ...[
                const SizedBox(height: AppSpacing.space5),
                const InlineAlert(
                  tone: InlineAlertTone.warning,
                  message:
                      'The rows that imported were saved. The list of '
                      'rejected rows could not be loaded — try importing the '
                      'remaining rows again.',
                ),
              ],
              // A count is not actionable. Which row, and why, is what lets
              // the admin fix the file and re-import.
              if (_rowErrors.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.space6),
                Text(
                  'Rejected rows',
                  style: AppTypography.sectionHeading.copyWith(
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  'Row numbers match your file, header included.',
                  style: AppTypography.bodyAdminMeta.copyWith(
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.space4),
                for (final row in _rowErrors) _RowErrorTile(error: row),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderHint extends StatelessWidget {
  const _HeaderHint();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Required header row',
            style: AppTypography.overline.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space2),
          SelectableText(
            ImportRepository.studentHeaders.join(','),
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'These names are case- and underscore-sensitive. A file using '
            'firstName instead of first_name is rejected row by row.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A multi-line paste area (the design system's [AppTextArea]).
class _PasteBox extends StatelessWidget {
  const _PasteBox({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppTextArea(
      controller: controller,
      enabled: enabled,
      minHeight: AppSizing.csvPasteMinHeight,
      semanticsLabel: 'CSV rows to import',
      semanticsHint:
          'First line is the header: '
          '${ImportRepository.studentHeaders.join(', ')}',
      placeholder:
          '${ImportRepository.studentHeaders.join(',')}\n'
          'Ayesha,Khan,2026-001',
    );
  }
}

class _RowErrorTile extends StatelessWidget {
  const _RowErrorTile({required this.error});

  final ImportRowError error;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints: const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Wrap(
        spacing: AppSpacing.space4,
        runSpacing: AppSpacing.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Row ${error.rowNumber}',
            style: AppTypography.personName.copyWith(color: t.textPrimary),
          ),
          Text(
            error.message,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
