import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/shell/campus_context.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../finance/domain/money.dart';
import '../data/academy_repository.dart';

/// Shared Academy UI plumbing. Frontend permission checks only shape the UI;
/// the server authorises every request (campus scope, instructor assignment,
/// learner ownership) and its answer always wins.

const academyManage = 'academy.manage';

/// Campuses (from `/api/campuses/mine`) where this account holds [permission].
List<CampusOption> campusesWith(BuildContext context, String permission) => [
  for (final c
      in CampusScope.maybeOf(context)?.options ?? const <CampusOption>[])
    if (c.permissions.contains(permission)) c,
];

bool canOnCampus(BuildContext context, String permission, String campusId) =>
    campusesWith(context, permission).any((c) => c.id == campusId);

String campusName(BuildContext context, String campusId) =>
    (CampusScope.maybeOf(context)?.options ?? const <CampusOption>[])
        .where((c) => c.id == campusId)
        .map((c) => c.name)
        .firstOrNull ??
    'Campus';

/// The campus a MUTATION targets: the explicit, still-authorised selection
/// among campuses where [permission] is held — or the only such campus.
/// Never the first of several (ADR-011). Null → ask the user to choose.
String? mutationCampus(BuildContext context, String permission) {
  final ids = [for (final c in campusesWith(context, permission)) c.id];
  return explicitCampusFor(context, ids);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Loads [load] into M1's [ScreenState] and renders it with [ScreenStateBuilder].
class AcademyLoader<T> extends StatefulWidget {
  const AcademyLoader({
    required this.load,
    required this.builder,
    required this.emptyTitle,
    required this.emptyMessage,
    this.isEmpty,
    this.emptyIcon = Icons.inbox_outlined,
    super.key,
  });

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T value,
    Future<void> Function() reload,
  )
  builder;
  final String emptyTitle, emptyMessage;
  final bool Function(T value)? isEmpty;
  final IconData emptyIcon;

  @override
  State<AcademyLoader<T>> createState() => AcademyLoaderState<T>();
}

class AcademyLoaderState<T> extends State<AcademyLoader<T>> {
  ScreenState<T> _state = ScreenState<T>.loading();

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => _state = ScreenState<T>.loading(previous: _state.data));
    try {
      final value = await widget.load();
      if (!mounted) return;
      // D-39: emptiness must be explicit for non-collection values.
      setState(
        () => _state = ScreenState<T>.data(
          value,
          isEmpty:
              widget.isEmpty?.call(value) ??
              (value is Iterable || value is Map ? null : false),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(
        () => _state = ScreenState<T>.failed(
          LoadFailure(
            message: AcademyRepository.explain(f),
            kind: f.kind,
            unreachable: f.unreachable,
          ),
          cached: _state.data,
          connection: f.unreachable
              ? NetworkStatus.offline
              : NetworkStatus.online,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ScreenStateBuilder<T>(
    state: _state,
    onRetry: reload,
    emptyTitle: widget.emptyTitle,
    emptyMessage: widget.emptyMessage,
    emptyIcon: widget.emptyIcon,
    data: (context, value) => widget.builder(context, value, reload),
  );
}

/// Small coloured status label, reusing the semantic tokens.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (Color bg, Color fg) = switch (status) {
      'open' ||
      'active' ||
      'present' ||
      'published' ||
      'held' => (t.successBg, t.successTextOnBg),
      'planned' ||
      'draft' ||
      'scheduled' ||
      'late' ||
      'leave' ||
      'excused' => (t.infoBg, t.textPrimary),
      'unmarked' => (t.warningBg, t.warningTextOnBg),
      'cancelled' || 'absent' || 'withdrawn' => (t.dangerBg, t.dangerTextOnBg),
      _ => (t.surfaceSunken, t.textSecondary),
    };
    return Semantics(
      label: 'Status $status',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space1,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(status, style: AppTypography.caption.copyWith(color: fg)),
      ),
    );
  }
}

/// Reports an Academy action's outcome. Shown INLINE, at the top of the
/// nearest [ResultBannerHost] (the design system's rule: no state is a
/// SnackBar or an overlay; an error must stay readable until dismissed).
/// Only where no host exists (e.g. a context from a dialog route) does it
/// fall back to a SnackBar.
void showResult(BuildContext context, String message, {bool error = false}) {
  final host = context.findAncestorStateOfType<ResultBannerHostState>();
  if (host != null) {
    host.show(message, error: error);
    return;
  }
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? context.tokens.danger : null,
    ),
  );
}

/// Hosts the inline outcome banner for [showResult] above [child].
/// [child] fills the remaining height, so the host must itself be bounded
/// (inside an Expanded or a Scaffold body).
class ResultBannerHost extends StatefulWidget {
  const ResultBannerHost({required this.child, super.key});

  final Widget child;

  @override
  State<ResultBannerHost> createState() => ResultBannerHostState();
}

class ResultBannerHostState extends State<ResultBannerHost> {
  String? _message;
  bool _error = false;

  void show(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space4,
              AppSpacing.space3,
              AppSpacing.space4,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InlineAlert(
                    tone: _error
                        ? InlineAlertTone.danger
                        : InlineAlertTone.success,
                    message: message,
                  ),
                ),
                AppButton(
                  key: const Key('result-banner-dismiss'),
                  label: 'Dismiss',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  semanticsLabel: 'Dismiss message',
                  onPressed: () => setState(() => _message = null),
                ),
              ],
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// A titled form in a dialog: [fields] edit local state; [submit] returns an
/// error message (shown inline, dialog stays open) or null on success.
Future<bool> showFormDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  required Widget Function(
    BuildContext context,
    void Function(void Function()) setState,
  )
  fields,
  required Future<String?> Function() submit,
  bool Function()? canSubmit,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      String? error;
      var busy = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: math.min(460.0, MediaQuery.sizeOf(context).width - 80),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fields(context, setState),
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.space5),
                    Text(
                      error!,
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: context.tokens.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: busy
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
            ),
            AppButton(
              label: busy ? 'Saving…' : submitLabel,
              onPressed: busy || !(canSubmit?.call() ?? true)
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      final message = await submit();
                      if (!dialogContext.mounted) return;
                      if (message == null) {
                        Navigator.of(dialogContext).pop(true);
                      } else {
                        setState(() {
                          busy = false;
                          error = message;
                        });
                      }
                    },
            ),
          ],
        ),
      );
    },
  );
  return ok ?? false;
}

/// Wraps a repository call for [showFormDialog]: null on success, readable text on failure.
Future<String?> attempt(Future<void> Function() call) async {
  try {
    await call();
    return null;
  } on Object catch (e) {
    final conflicts = AcademyRepository.conflicts(e);
    if (conflicts.isNotEmpty) return conflicts.join('\n');
    return AcademyRepository.explain(e);
  }
}

/// AppTextField bound to a mutable string via a setter.
Widget field(
  String label,
  String value,
  void Function(String) onChanged, {
  String? placeholder,
  bool required = false,
  String? error,
}) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.space5),
  child: AppTextField(
    label: label,
    value: value,
    placeholder: placeholder,
    required: required,
    onChanged: onChanged,
    errorText: error,
    state: error == null ? AppTextFieldState.normal : AppTextFieldState.error,
  ),
);

/// A labelled dropdown in the M1 field style.
Widget dropdown<T>(
  String label,
  T? value,
  List<(T, String)> items,
  void Function(T?) onChanged,
) => Padding(
  padding: const EdgeInsets.only(bottom: AppSpacing.space5),
  child: DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final (v, l) in items)
        DropdownMenuItem<T>(
          value: v,
          child: Text(l, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
  ),
);

final _decimal = RegExp(r'^\d{1,9}(\.\d{1,2})?$');
bool isDecimal2(String s) => _decimal.hasMatch(s.trim());
final _time = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
bool isTime(String s) => _time.hasMatch(s.trim());
final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
bool isDate(String s) =>
    _date.hasMatch(s.trim()) && DateTime.tryParse(s.trim()) != null;

/// The campus-switcher selection, used only to NARROW list reads, and only when
/// this account holds [permission] there (otherwise the server would 404).
/// Null = every authorised campus. Read during build, never in initState.
String? listCampus(BuildContext context, String permission) {
  final selected = CampusScope.maybeOf(context)?.selectedId;
  return selected != null && canOnCampus(context, permission, selected)
      ? selected
      : null;
}

/// Reloads [loader] after the frame whenever [campus] changes.
class CampusReload {
  String? _last;
  bool _seen = false;
  void track(String? campus, GlobalKey<AcademyLoaderState<dynamic>> loader) {
    if (_seen && campus != _last) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => loader.currentState?.reload(),
      );
    }
    _seen = true;
    _last = campus;
  }
}

/// Loads data a form needs before opening it; on failure shows the reason and
/// returns null, so the form never opens half-populated.
Future<T?> loadForForm<T>(
  BuildContext context,
  Future<T> Function() load,
) async {
  try {
    return await load();
  } on Object catch (e) {
    if (context.mounted) {
      showResult(
        context,
        AcademyRepository.explain(e, 'Could not load the form.'),
        error: true,
      );
    }
    return null;
  }
}

/// Exact PKR display of a server decimal string. `Money.format` already adds
/// the "PKR" prefix; an unparseable value is shown verbatim, never rounded.
String pkr(String raw) => Money.tryParse(raw)?.format() ?? 'PKR $raw';
