import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/motion_reveal.dart';
import '../data/attendance_repository.dart';

/// "Your classes": every register this teacher may open, timetable or not
/// (hard-QA BUG-QA-11).
///
/// Before this, a register opened only from a timetabled period on Today, so
/// a teacher in an institution that had not built a timetable (common in the
/// first weeks of a session, and for coaching centres that never do) could
/// not take attendance at all. The list comes from the server's own
/// teaching-assignment rules (`/api/attendance/my-sections`), so it never
/// offers a class the server would refuse. Hidden while loading, when empty
/// and on failure: the timetable path still works, and an error here must
/// not hide it.
class MyRegistersPanel extends StatefulWidget {
  const MyRegistersPanel({required this.repository, required this.onOpen, super.key});

  final AttendanceRepository repository;
  final void Function(MyRegister register) onOpen;

  @override
  State<MyRegistersPanel> createState() => _MyRegistersPanelState();
}

class _MyRegistersPanelState extends State<MyRegistersPanel> {
  List<MyRegister> _registers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.repository.mySections();
      if (mounted) setState(() => _registers = list);
    } on Object {
      // Leave it hidden; see the class doc.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_registers.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    // M1 motion: arrives once when the list loads; reduced motion = fade only.
    return MotionReveal(child: Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.space6, 0, AppSpacing.space6, AppSpacing.space4),
      child: Column(
        key: const Key('my-registers'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your classes', style: AppTypography.sectionHeading.copyWith(color: t.textPrimary)),
          const SizedBox(height: AppSpacing.space2),
          for (final r in _registers)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space2),
              child: Semantics(
                button: true,
                label: 'Open register for ${r.label}',
                excludeSemantics: true,
                child: Material(
                  color: t.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    side: BorderSide(color: t.border, width: AppSizing.borderThin),
                  ),
                  child: InkWell(
                    key: Key('open-register-${r.sectionId}'),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    onTap: () => widget.onOpen(r),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppSizing.touchTargetMin),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5, vertical: AppSpacing.space3),
                        child: Row(
                          children: [
                            Icon(Icons.fact_check_outlined, color: t.textSecondary),
                            const SizedBox(width: AppSpacing.space4),
                            Expanded(
                              child: Text(r.label, style: AppTypography.personName.copyWith(color: t.textPrimary)),
                            ),
                            Text('Register', style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary)),
                            Icon(Icons.chevron_right, color: t.textSecondary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ));
  }
}
