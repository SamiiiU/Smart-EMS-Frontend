import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';

/// Which kind of person the new login belongs to.
enum WizardRole {
  teacher('teacher', 'Teacher'),
  student('student', 'Student'),
  parent('parent', 'Parent');

  const WizardRole(this.wire, this.label);

  final String wire;
  final String label;
}

/// Where a run of the wizard got to.
///
/// This exists because D-17's real case is PARTIAL failure: the login is
/// created, then linking the person record fails. The account exists from
/// that moment on, so restarting from the beginning hits "username already
/// taken" and strands the admin with an orphan account they can neither see
/// nor fix. Carrying [userId] forward is what makes the retry resumable.
enum WizardStage {
  /// Nothing written yet. Everything is still local to the form.
  collecting,

  /// `POST /api/users/provision` succeeded; the person record has not been
  /// created or linked yet. THIS is the dangerous state.
  userCreated,

  /// Both writes done.
  complete,
}

/// The outcome of committing the wizard.
sealed class WizardOutcome {
  const WizardOutcome();
}

class WizardSucceeded extends WizardOutcome {
  const WizardSucceeded({required this.userId});

  final String userId;
}

/// The login exists but its person record does not — the orphan condition
/// `UnlinkedProfileState` renders from the other side. Recoverable, and the
/// [userId] is the thing that makes it recoverable.
class WizardPartiallyFailed extends WizardOutcome {
  const WizardPartiallyFailed({
    required this.userId,
    required this.failure,
  });

  final String userId;
  final LoadFailure failure;
}

/// Nothing was written. Safe to retry from the start.
class WizardFailed extends WizardOutcome {
  const WizardFailed(this.failure);

  final LoadFailure failure;
}

/// Everything the wizard collects before anything is written.
class WizardDraft {
  WizardDraft({
    required this.role,
    required this.username,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.campusId,
    this.email,
    this.employeeCode,
    this.admissionNumber,
    this.relationship,
    this.linkedStudentId,
  });

  final WizardRole role;
  final String username;
  final String password;
  final String firstName;
  final String lastName;
  final String campusId;
  final String? email;
  final String? employeeCode;
  final String? admissionNumber;
  final String? relationship;

  /// Parents attach to an existing student rather than creating one.
  final String? linkedStudentId;
}

/// Creates a login and its person record, as one deferred commit.
///
/// **Nothing is written until [commit] is called.** The wizard's steps only
/// fill in a [WizardDraft]; abandoning it halfway leaves no trace.
class UserWizardRepository {
  const UserWizardRepository(this.dio);

  final Dio dio;

  /// Commits the draft.
  ///
  /// [existingUserId] resumes a previous run that failed after the login was
  /// created — pass the id from [WizardPartiallyFailed] and the provision
  /// step is SKIPPED entirely. Re-provisioning would fail on the duplicate
  /// username and, worse, a caller that "handled" that by generating a new
  /// username would leave two accounts for one person.
  Future<WizardOutcome> commit(
    WizardDraft draft, {
    String? existingUserId,
  }) async {
    String userId;

    if (existingUserId != null) {
      userId = existingUserId;
    } else {
      try {
        final res = await dio.post<Map<String, dynamic>>(
          ApiConfig.provisionPath,
          data: {
            'username': draft.username,
            'password': draft.password,
            'role': draft.role.wire,
            if (draft.email != null && draft.email!.isNotEmpty)
              'email': draft.email,
          },
        );
        final created = res.data?['userId'] as String?;
        if (created == null) {
          return const WizardFailed(
            LoadFailure(message: 'The server did not return a user id.'),
          );
        }
        userId = created;
      } on DioException catch (err) {
        // Nothing was written — a clean restart is safe here.
        return WizardFailed(mapDioError(err));
      }
    }

    // From here on the login EXISTS. Every failure below is partial, and
    // must hand the userId back rather than reporting a plain error.
    try {
      await _createPersonRecord(draft, userId);
      return WizardSucceeded(userId: userId);
    } on DioException catch (err) {
      return WizardPartiallyFailed(
        userId: userId,
        failure: mapDioError(err),
      );
    }
  }

  Future<void> _createPersonRecord(WizardDraft draft, String userId) async {
    switch (draft.role) {
      case WizardRole.teacher:
        await dio.post<Map<String, dynamic>>(
          ApiConfig.staffPath,
          data: {
            'firstName': draft.firstName,
            'lastName': draft.lastName,
            'employeeCode': draft.employeeCode,
            'campusId': draft.campusId,
            'userId': userId,
          },
        );
      case WizardRole.student:
        await dio.post<Map<String, dynamic>>(
          ApiConfig.studentsPath,
          data: {
            'firstName': draft.firstName,
            'lastName': draft.lastName,
            'admissionNumber': draft.admissionNumber,
            'campusId': draft.campusId,
            'userId': userId,
          },
        );
      case WizardRole.parent:
        await dio.post<Map<String, dynamic>>(
          ApiConfig.guardiansPath,
          data: {
            'studentId': draft.linkedStudentId,
            'firstName': draft.firstName,
            'lastName': draft.lastName,
            'relationship': draft.relationship ?? 'guardian',
            'userId': userId,
          },
        );
    }
  }
}
