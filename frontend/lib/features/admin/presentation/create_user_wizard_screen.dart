import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../data/user_wizard_repository.dart';

/// Creates a login and its person record.
///
/// **Deferred commit (D-17).** Every step only fills in a [WizardDraft];
/// nothing is written until the admin confirms on the last step. Abandoning
/// the wizard halfway leaves no trace.
///
/// **Recovery is the part that matters.** The commit is two writes — the
/// login, then the person record — and the second one can fail after the
/// first succeeded. From that instant the account EXISTS, so:
///
///   - restarting from step one hits "username already taken";
///   - "fixing" that by picking a new username creates a SECOND account for
///     one person;
///   - and abandoning it leaves an orphan login with no person record,
///     which is exactly what `UnlinkedProfileState` renders from the other
///     side. The wizard is where those get created, so it is where they
///     have to be prevented.
///
/// So on partial failure this screen keeps the returned `userId`, says
/// plainly what did and did not happen, and offers to resume the failed
/// step — never to start over.
class CreateUserWizardScreen extends StatefulWidget {
  const CreateUserWizardScreen({
    required this.repository,
    required this.campusId,
    this.onFinished,
    super.key,
  });

  final UserWizardRepository repository;
  final String campusId;
  final VoidCallback? onFinished;

  @override
  State<CreateUserWizardScreen> createState() => CreateUserWizardScreenState();
}

class CreateUserWizardScreenState extends State<CreateUserWizardScreen> {
  static const int _lastStep = 2;

  int _step = 0;

  WizardRole _role = WizardRole.teacher;
  String _username = '';
  String _password = '';
  String _firstName = '';
  String _lastName = '';
  String _email = '';
  String _employeeCode = '';
  String _admissionNumber = '';
  String _linkedStudentId = '';

  bool _submitting = false;
  String? _error;
  bool _done = false;

  /// Non-null once the login has been created. Its presence IS the recovery
  /// state: it means a retry must resume, not restart.
  String? _createdUserId;

  bool get _isRecovering => _createdUserId != null && !_done;

  bool get _identityComplete =>
      _username.trim().isNotEmpty && _password.isNotEmpty;

  bool get _detailsComplete {
    if (_firstName.trim().isEmpty || _lastName.trim().isEmpty) return false;
    return switch (_role) {
      WizardRole.teacher => _employeeCode.trim().isNotEmpty,
      WizardRole.student => _admissionNumber.trim().isNotEmpty,
      WizardRole.parent => _linkedStudentId.trim().isNotEmpty,
    };
  }

  WizardDraft get _draft => WizardDraft(
        role: _role,
        username: _username.trim(),
        password: _password,
        firstName: _firstName.trim(),
        lastName: _lastName.trim(),
        campusId: widget.campusId,
        email: _email.trim().isEmpty ? null : _email.trim(),
        employeeCode: _employeeCode.trim(),
        admissionNumber: _admissionNumber.trim(),
        relationship: 'guardian',
        linkedStudentId:
            _linkedStudentId.trim().isEmpty ? null : _linkedStudentId.trim(),
      );

  Future<void> commit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final outcome = await widget.repository.commit(
      _draft,
      // The whole point: on a resume this is non-null, so provisioning is
      // skipped and no second account can be created.
      existingUserId: _createdUserId,
    );

    if (!mounted) return;

    switch (outcome) {
      case WizardSucceeded(:final userId):
        setState(() {
          _submitting = false;
          _createdUserId = userId;
          _done = true;
        });
        widget.onFinished?.call();
      case WizardPartiallyFailed(:final userId, :final failure):
        setState(() {
          _submitting = false;
          // Kept so the retry resumes rather than restarts.
          _createdUserId = userId;
          _error = failure.message ?? 'Could not link the record.';
        });
      case WizardFailed(:final failure):
        setState(() {
          _submitting = false;
          _error = failure.message ?? 'Could not create the account.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppSizing.authFormMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create a user',
                  style: AppTypography.screenTitle
                      .copyWith(color: t.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  _done
                      ? 'Done.'
                      : 'Step ${_step + 1} of ${_lastStep + 1} · nothing is '
                          'saved until you confirm',
                  style: AppTypography.bodyAdminMeta
                      .copyWith(color: t.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space6),

                if (_done) ...[
                  const InlineAlert(
                    tone: InlineAlertTone.success,
                    message: 'The account and its record were created.',
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  AppButton(
                    label: 'Done',
                    fullWidth: true,
                    onPressed: () => setState(_reset),
                  ),
                ] else ...[
                  // The recovery notice. Deliberately explicit about which
                  // half succeeded — an admin who cannot tell will either
                  // retry blindly or abandon an orphan account.
                  if (_isRecovering) ...[
                    InlineAlert(
                      tone: InlineAlertTone.warning,
                      message: 'The login “$_username” was created, but its '
                          'record could not be linked. Retrying will resume '
                          'from that step — it will not create a second '
                          'account.',
                    ),
                    const SizedBox(height: AppSpacing.space5),
                  ],
                  if (_error != null) ...[
                    InlineAlert(
                      tone: InlineAlertTone.danger,
                      message: _error!,
                    ),
                    const SizedBox(height: AppSpacing.space5),
                  ],
                  ..._stepBody(context),
                  const SizedBox(height: AppSpacing.space8),
                  _controls(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _reset() {
    _step = 0;
    _username = '';
    _password = '';
    _firstName = '';
    _lastName = '';
    _email = '';
    _employeeCode = '';
    _admissionNumber = '';
    _linkedStudentId = '';
    _createdUserId = null;
    _error = null;
    _done = false;
  }

  List<Widget> _stepBody(BuildContext context) {
    final fieldState =
        _submitting ? AppTextFieldState.disabled : AppTextFieldState.normal;

    switch (_step) {
      case 0:
        return [
          Text(
            'Role',
            style: AppTypography.fieldLabel
                .copyWith(color: context.tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space3),
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space3,
            children: [
              for (final role in WizardRole.values)
                _RoleChip(
                  role: role,
                  selected: role == _role,
                  // Locked once the login exists: the role was baked into
                  // the account at provision time, so changing it now would
                  // silently disagree with what was written.
                  enabled: !_submitting && !_isRecovering,
                  onTap: () => setState(() => _role = role),
                ),
            ],
          ),
        ];
      case 1:
        return [
          AppTextField(
            label: 'Username',
            value: _username,
            state: _isRecovering ? AppTextFieldState.disabled : fieldState,
            textInputAction: TextInputAction.next,
            onChanged: (v) => setState(() => _username = v),
          ),
          const SizedBox(height: AppSpacing.space5),
          AppTextField(
            label: 'Temporary password',
            value: _password,
            obscure: true,
            state: _isRecovering ? AppTextFieldState.disabled : fieldState,
            onChanged: (v) => setState(() => _password = v),
          ),
          const SizedBox(height: AppSpacing.space5),
          AppTextField(
            label: 'Email (optional)',
            value: _email,
            state: _isRecovering ? AppTextFieldState.disabled : fieldState,
            onChanged: (v) => setState(() => _email = v),
          ),
        ];
      default:
        return [
          AppTextField(
            label: 'First name',
            value: _firstName,
            state: fieldState,
            textInputAction: TextInputAction.next,
            onChanged: (v) => setState(() => _firstName = v),
          ),
          const SizedBox(height: AppSpacing.space5),
          AppTextField(
            label: 'Last name',
            value: _lastName,
            state: fieldState,
            onChanged: (v) => setState(() => _lastName = v),
          ),
          const SizedBox(height: AppSpacing.space5),
          switch (_role) {
            WizardRole.teacher => AppTextField(
                label: 'Employee code',
                value: _employeeCode,
                state: fieldState,
                onChanged: (v) => setState(() => _employeeCode = v),
              ),
            WizardRole.student => AppTextField(
                label: 'Admission number',
                value: _admissionNumber,
                state: fieldState,
                onChanged: (v) => setState(() => _admissionNumber = v),
              ),
            WizardRole.parent => AppTextField(
                label: 'Student ID to link',
                value: _linkedStudentId,
                state: fieldState,
                onChanged: (v) => setState(() => _linkedStudentId = v),
              ),
          },
        ];
    }
  }

  Widget _controls(BuildContext context) {
    final onLast = _step == _lastStep;
    final canAdvance = switch (_step) {
      0 => true,
      1 => _identityComplete,
      _ => _detailsComplete,
    };

    return Row(
      children: [
        if (_step > 0 && !_isRecovering)
          Expanded(
            child: AppButton(
              label: 'Back',
              variant: AppButtonVariant.secondary,
              fullWidth: true,
              onPressed: _submitting ? null : () => setState(() => _step--),
            ),
          ),
        if (_step > 0 && !_isRecovering)
          const SizedBox(width: AppSpacing.space4),
        Expanded(
          child: AppButton(
            label: _submitting
                ? 'Saving…'
                : onLast
                    ? (_isRecovering ? 'Resume' : 'Create')
                    : 'Next',
            fullWidth: true,
            onPressed: !canAdvance || _submitting
                ? null
                : onLast
                    ? commit
                    : () => setState(() => _step++),
          ),
        ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.role,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final WizardRole role;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bg = selected ? t.primarySubtle : t.surface;
    final fg = enabled
        ? (selected ? t.textPrimary : t.textSecondary)
        : t.textDisabled;
    final border = selected ? t.primaryAccent : t.border;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: role.label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space3,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: border),
            ),
            child: Text(
              role.label,
              style: AppTypography.fieldLabel.copyWith(color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
