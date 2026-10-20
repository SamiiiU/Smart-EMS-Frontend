import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/business_date.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../core/widgets/states/loading_skeleton.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/domain/setup_models.dart';
import '../../setup/presentation/sections_screen.dart' show PickerChip;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/academics_repository.dart';
import '../data/subject_resources_repository.dart';
import '../data/teacher_syllabus_context.dart';

/// D-21 Subject resources (School/College): books, notes and links for one
/// subject in one class, in the working academic year.
///
/// The server decides every permission. A teacher sees and manages only the
/// subjects and classes they are assigned; a campus administrator manages the
/// campus; students and guardians read through their own screens. This screen
/// shows Add only to staff, and Delete only where the server says it may.
class SubjectResourcesScreen extends StatefulWidget {
  const SubjectResourcesScreen({
    required this.repository,
    required this.year,
    required this.classes,
    required this.subjects,
    super.key,
  });

  final SubjectResourcesRepository repository;
  final AcademicYear year;
  final List<SchoolClass> classes;
  final List<Subject> subjects;

  @override
  State<SubjectResourcesScreen> createState() => SubjectResourcesScreenState();
}

class SubjectResourcesScreenState extends State<SubjectResourcesScreen> {
  String? _classId;
  String? _subjectId;
  ScreenState<List<SubjectResource>> _state =
      const ScreenState<List<SubjectResource>>.loading();
  String? _notice;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _classId = widget.classes.isEmpty ? null : widget.classes.first.id;
    _subjectId = widget.subjects.isEmpty ? null : widget.subjects.first.id;
    _load();
  }

  Future<void> _load() async {
    final classId = _classId, subjectId = _subjectId;
    if (classId == null || subjectId == null) return;
    setState(
      () => _state = ScreenState<List<SubjectResource>>.loading(
        previous: _state.data,
      ),
    );
    try {
      final items = await widget.repository.list(
        subjectId: subjectId,
        classId: classId,
        academicYearId: widget.year.id,
      );
      if (!mounted || classId != _classId || subjectId != _subjectId) return;
      setState(() => _state = ScreenState<List<SubjectResource>>.data(items));
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _state = ScreenState<List<SubjectResource>>.failed(
          e is LoadFailure ? e : const LoadFailure(),
          cached: _state.data,
        ),
      );
    }
  }

  void _select({String? classId, String? subjectId}) {
    setState(() {
      _classId = classId ?? _classId;
      _subjectId = subjectId ?? _subjectId;
      _notice = null;
      _actionError = null;
    });
    _load();
  }

  Future<void> _add({required bool link}) async {
    final classId = _classId, subjectId = _subjectId;
    if (classId == null || subjectId == null) return;
    final added = await showAppSheet<bool>(
      context,
      title: link ? 'Add a link' : 'Add a file',
      builder: (_) => _AddResourceSheet(
        repository: widget.repository,
        subjectId: subjectId,
        classId: classId,
        academicYearId: widget.year.id,
        link: link,
      ),
    );
    if (added == true && mounted) {
      setState(() {
        _notice = link ? 'Link added.' : 'File added.';
        _actionError = null;
      });
      await _load();
    }
  }

  Future<void> _save(SubjectResource r) async {
    final error = await saveSubjectResource(widget.repository, r);
    if (error != null && mounted) setState(() => _actionError = error);
  }

  Future<void> _copyLink(SubjectResource r) async {
    final url = r.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) setState(() => _notice = 'Link copied.');
  }

  Future<void> _delete(SubjectResource r) async {
    final ok = await confirmAction(
      context,
      title: 'Remove this resource?',
      message:
          '“${r.title}” will no longer be available to staff, students '
          'or guardians.',
      confirmLabel: 'Remove',
      irreversible: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.repository.delete(r.id);
      if (!mounted) return;
      setState(() {
        _notice = 'Resource removed.';
        _actionError = null;
      });
      await _load();
    } on LoadFailure catch (f) {
      if (mounted) {
        setState(
          () =>
              _actionError = f.message ?? 'The resource could not be removed.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ready = _classId != null && _subjectId != null;
    return SetupScaffold(
      title: 'Subject resources',
      note: InlineAlert(
        tone: InlineAlertTone.info,
        message:
            'Books, notes and links for ${widget.year.name}. Files are '
            'private: only staff of the subject and the class’s students and '
            'guardians can open them.',
      ),
      children: [
        _picker(context, 'Class', [
          for (final c in widget.classes)
            PickerChip(
              label: c.name,
              selected: c.id == _classId,
              onTap: () => _select(classId: c.id),
            ),
        ]),
        _picker(context, 'Subject', [
          for (final s in widget.subjects)
            PickerChip(
              label: s.name,
              selected: s.id == _subjectId,
              onTap: () => _select(subjectId: s.id),
            ),
        ]),
        if (!ready)
          Text(
            'Choose a class and a subject.',
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          )
        else ...[
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space3,
            children: [
              AppButton(
                key: const Key('resource-add-file'),
                label: 'Add a file',
                icon: Icons.upload_file_outlined,
                onPressed: () => _add(link: false),
              ),
              AppButton(
                key: const Key('resource-add-link'),
                label: 'Add a link',
                variant: AppButtonVariant.secondary,
                icon: Icons.link,
                onPressed: () => _add(link: true),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          if (_notice != null) ...[
            InlineAlert(tone: InlineAlertTone.success, message: _notice!),
            const SizedBox(height: AppSpacing.space3),
          ],
          if (_actionError != null) ...[
            InlineAlert(tone: InlineAlertTone.danger, message: _actionError!),
            const SizedBox(height: AppSpacing.space3),
          ],
          ScreenStateBuilder<List<SubjectResource>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No resources yet',
            emptyMessage:
                'Files and links added for this subject and class '
                'appear here.',
            emptyIcon: Icons.folder_outlined,
            data: (context, items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in items)
                  ResourceRow(
                    resource: r,
                    onSave: r.isLink || r.isPending ? null : () => _save(r),
                    onCopy: r.isLink ? () => _copyLink(r) : null,
                    onDelete: r.canDelete ? () => _delete(r) : null,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _picker(BuildContext context, String label, List<Widget> chips) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.fieldLabel.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: chips,
          ),
        ],
      ),
    );
  }
}

/// Downloads a file resource through the authenticated private-file gateway
/// and hands it to the system save dialog (Android) or a browser download
/// (Web). Returns a user-facing error, or null on success or cancel.
Future<String?> saveSubjectResource(
  SubjectResourcesRepository repository,
  SubjectResource r,
) async {
  final fileId = r.fileId;
  if (fileId == null) return null;
  try {
    final bytes = await repository.download(fileId);
    await FilePicker.saveFile(
      fileName: r.filename ?? '${r.title}.bin',
      bytes: bytes,
      mimeType: r.contentType ?? 'application/octet-stream',
    );
    return null;
  } on LoadFailure catch (f) {
    return f.message ?? 'The file could not be downloaded.';
  } on Object catch (_) {
    return 'The file could not be saved.';
  }
}

/// One resource: title, type, size, date, and only the actions given.
class ResourceRow extends StatelessWidget {
  const ResourceRow({
    required this.resource,
    this.onSave,
    this.onCopy,
    this.onDelete,
    super.key,
  });

  final SubjectResource resource;
  final VoidCallback? onSave;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

  static String _size(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _type(SubjectResource r) {
    if (r.isLink) return 'Link';
    final name = r.filename ?? '';
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'File' : name.substring(dot + 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = resource;
    final date = r.createdAt == null || r.createdAt!.length < 10
        ? null
        : formatBusinessDate(context, r.createdAt!.substring(0, 10));
    final meta = [
      _type(r),
      if (!r.isLink && r.sizeBytes != null) _size(r.sizeBytes),
      ?date,
      if (r.isPending) 'Upload not finished',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: t.border, width: AppSizing.borderThin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                r.isLink ? Icons.link : Icons.insert_drive_file_outlined,
                color: t.textSecondary,
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: AppTypography.cardHeading.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      meta,
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                    if (r.isLink && r.url != null)
                      SelectableText(
                        r.url!,
                        style: AppTypography.bodyAdminMeta.copyWith(
                          color: t.textPrimary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space3),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              if (onSave != null)
                AppButton(
                  label: 'Download',
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  icon: Icons.download_outlined,
                  semanticsLabel: 'Download ${r.title}',
                  onPressed: onSave,
                ),
              if (onCopy != null)
                AppButton(
                  label: 'Copy link',
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.sm,
                  icon: Icons.copy_outlined,
                  semanticsLabel: 'Copy the link for ${r.title}',
                  onPressed: onCopy,
                ),
              if (onDelete != null)
                AppButton(
                  label: 'Remove',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  semanticsLabel: 'Remove ${r.title}',
                  onPressed: onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Title + file (or https link), validated before any request; upload shows progress.
class _AddResourceSheet extends StatefulWidget {
  const _AddResourceSheet({
    required this.repository,
    required this.subjectId,
    required this.classId,
    required this.academicYearId,
    required this.link,
  });

  final SubjectResourcesRepository repository;
  final String subjectId;
  final String classId;
  final String academicYearId;
  final bool link;

  @override
  State<_AddResourceSheet> createState() => _AddResourceSheetState();
}

class _AddResourceSheetState extends State<_AddResourceSheet> {
  // Stable across retries of the same add, so a lost response never duplicates.
  final String _createKey = const Uuid().v4();
  final String _uploadKey = const Uuid().v4();
  String? _resourceId;

  String _title = '';
  String _url = '';
  PlatformFile? _file;
  Uint8List? _bytes;
  double? _progress;
  bool _busy = false;
  String? _error;

  bool get _valid {
    final title = _title.trim();
    if (title.isEmpty || title.length > 120) return false;
    if (widget.link) return _url.trim().startsWith('https://');
    return _bytes != null;
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: SubjectResourcesRepository.allowedExtensions,
    );
    if (file == null || !mounted) return;
    final ext = file.name.contains('.')
        ? file.name.substring(file.name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    if (!SubjectResourcesRepository.allowedExtensions.contains(ext)) {
      setState(
        () => _error =
            'Use a PDF, image (PNG/JPG), Word, Excel, '
            'PowerPoint or text file.',
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.isEmpty || bytes.length > SubjectResourcesRepository.maxBytes) {
      setState(() => _error = 'The file must be smaller than 8 MB.');
      return;
    }
    setState(() {
      _file = file;
      _bytes = bytes;
      _error = null;
      if (_title.trim().isEmpty) {
        final dot = file.name.lastIndexOf('.');
        _title = dot > 0 ? file.name.substring(0, dot) : file.name;
      }
    });
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = widget.link ? null : 0;
    });
    try {
      _resourceId ??= await widget.repository.create(
        subjectId: widget.subjectId,
        classId: widget.classId,
        academicYearId: widget.academicYearId,
        title: _title.trim(),
        requestKey: _createKey,
        kind: widget.link ? 'link' : 'file',
        url: widget.link ? _url.trim() : null,
      );
      if (!widget.link) {
        await widget.repository.uploadAndAttach(
          resourceId: _resourceId!,
          bytes: _bytes!,
          filename: _file!.name,
          uploadKey: _uploadKey,
          onProgress: (sent, total) {
            if (mounted && total > 0) setState(() => _progress = sent / total);
          },
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on LoadFailure catch (f) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = f.message ?? 'It could not be added. Try again.';
        });
      }
    } on Object catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'It could not be added. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            key: const Key('resource-title'),
            label: 'Title',
            required: true,
            value: _title,
            placeholder: 'e.g. Chapter 3 worksheet',
            onChanged: (v) => setState(() => _title = v),
          ),
          const SizedBox(height: AppSpacing.space4),
          if (widget.link)
            AppTextField(
              key: const Key('resource-url'),
              label: 'Link (https://)',
              required: true,
              value: _url,
              keyboardType: TextInputType.url,
              placeholder: 'https://',
              onChanged: (v) => setState(() => _url = v),
            )
          else ...[
            AppButton(
              key: const Key('resource-pick'),
              label: _file == null ? 'Choose a file' : 'Choose another file',
              variant: AppButtonVariant.secondary,
              icon: Icons.attach_file,
              onPressed: _busy ? null : _pick,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              _file == null
                  ? 'PDF, PNG, JPG, Word, Excel, PowerPoint or text. Up to 8 MB.'
                  : '${_file!.name} · ${ResourceRow._size(_bytes?.length)}',
              style: AppTypography.bodyAdminMeta.copyWith(
                color: t.textSecondary,
              ),
            ),
          ],
          if (_progress != null && _busy) ...[
            const SizedBox(height: AppSpacing.space4),
            Semantics(
              label: 'Uploading, ${((_progress ?? 0) * 100).round()} percent',
              child: ProgressBar(percent: (_progress!.clamp(0.0, 1.0)) * 100),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.space4),
            InlineAlert(tone: InlineAlertTone.danger, message: _error!),
          ],
          const SizedBox(height: AppSpacing.space6),
          AppButton(
            key: const Key('resource-submit'),
            label: _busy ? 'Adding…' : 'Add',
            fullWidth: true,
            onPressed: _valid && !_busy ? _submit : null,
          ),
        ],
      ),
    );
  }
}

/// Teacher entry: the teacher's own assigned classes and subjects (same source
/// as Syllabus), then the resources screen.
class TeacherResourcesFlow extends StatefulWidget {
  const TeacherResourcesFlow({
    required this.academics,
    required this.staffId,
    super.key,
  });

  final AcademicsRepository academics;
  final String? staffId;

  @override
  State<TeacherResourcesFlow> createState() => _TeacherResourcesFlowState();
}

class _TeacherResourcesFlowState extends State<TeacherResourcesFlow> {
  TeacherSyllabusContext? _context;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final staffId = widget.staffId;
      final c = staffId == null
          ? null
          : await widget.academics.teacherSyllabusContext(staffId);
      if (mounted) setState(() => _context = c);
    } on LoadFailure catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message ?? 'Your subjects could not be loaded.',
        );
      }
    } on Object catch (_) {
      if (mounted) {
        setState(() => _error = 'Your subjects could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _context;
    if (_loading) {
      return const SetupScaffold(
        title: 'Subject resources',
        children: [LoadingSkeleton.listRows(count: 3)],
      );
    }
    if (_error != null) {
      return SetupScaffold(
        title: 'Subject resources',
        children: [
          InlineAlert(tone: InlineAlertTone.danger, message: _error!),
          const SizedBox(height: AppSpacing.space4),
          AppButton(label: 'Try again', onPressed: _load),
        ],
      );
    }
    if (c == null || c.isEmpty) {
      return const SetupScaffold(
        title: 'Subject resources',
        children: [
          InlineAlert(
            tone: InlineAlertTone.info,
            message:
                'You have no current teaching assignment, so there are '
                'no subjects to add resources to.',
          ),
        ],
      );
    }
    return SubjectResourcesScreen(
      repository: SubjectResourcesRepository(widget.academics.dio),
      year: c.year,
      classes: c.classes,
      subjects: c.subjects,
    );
  }
}
