import 'package:dio/dio.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';

/// Overhaul M4: admitting a learner WITHOUT a login (most learners never sign in).
///
/// Three existing endpoints, called in order: create the student record, enrol
/// it in a section for the academic year, then (optionally) add a guardian.
/// The submission is RESUMABLE: once the student exists its id is kept, so a
/// retry after a failed later step never creates a second student.
class AdmissionDraft {
  String firstName = '';
  String lastName = '';
  String admissionNumber = '';
  String? campusId;
  String? academicYearId;
  String? sectionId;
  String rollNumber = '';
  bool addGuardian = true;
  String guardianFirstName = '';
  String guardianLastName = '';
  String relationship = 'father';

  bool get learnerReady =>
      firstName.trim().isNotEmpty && lastName.trim().isNotEmpty && admissionNumber.trim().isNotEmpty;
  bool get placementReady => campusId != null && academicYearId != null && sectionId != null;
  bool get guardianReady =>
      !addGuardian || (guardianFirstName.trim().isNotEmpty && guardianLastName.trim().isNotEmpty);
}

/// Progress of one admission, kept by the screen across retries.
class AdmissionProgress {
  String? studentId;
  bool enrolled = false;
  bool guardianAdded = false;
  bool get started => studentId != null;
}

sealed class AdmissionOutcome {
  const AdmissionOutcome();
}

class AdmissionDone extends AdmissionOutcome {
  const AdmissionDone(this.studentId);
  final String studentId;
}

/// [step] names what failed; everything before it is saved and is not repeated.
class AdmissionFailed extends AdmissionOutcome {
  const AdmissionFailed(this.step, this.failure);
  final String step;
  final LoadFailure failure;
}

class AdmissionRepository {
  const AdmissionRepository(this.dio);
  final Dio dio;

  Future<AdmissionOutcome> submit(AdmissionDraft d, AdmissionProgress p) async {
    if (p.studentId == null) {
      try {
        final res = await dio.post<Map<String, dynamic>>(ApiConfig.studentsPath, data: {
          'campusId': d.campusId,
          'admissionNumber': d.admissionNumber.trim(),
          'firstName': d.firstName.trim(),
          'lastName': d.lastName.trim(),
        });
        final id = res.data?['id'] as String?;
        if (id == null) return const AdmissionFailed('learner', LoadFailure(message: 'The server did not return a learner id.'));
        p.studentId = id;
      } on DioException catch (e) {
        final f = mapDioError(e);
        if (e.response?.statusCode == 409) {
          return AdmissionFailed('learner',
              LoadFailure(message: 'Admission number ${d.admissionNumber.trim()} is already in use. Use a different number.'));
        }
        return AdmissionFailed('learner', f);
      }
    }
    if (!p.enrolled) {
      try {
        await dio.post<dynamic>(ApiConfig.enrollmentsPath, data: {
          'studentId': p.studentId,
          'sectionId': d.sectionId,
          'academicYearId': d.academicYearId,
          if (d.rollNumber.trim().isNotEmpty) 'rollNumber': d.rollNumber.trim(),
        });
        p.enrolled = true;
      } on DioException catch (e) {
        // 409 = already enrolled for this year (e.g. a retry whose response was lost).
        if (e.response?.statusCode != 409) return AdmissionFailed('placement', mapDioError(e));
        p.enrolled = true;
      }
    }
    if (d.addGuardian && !p.guardianAdded) {
      try {
        await dio.post<dynamic>(ApiConfig.guardiansPath, data: {
          'studentId': p.studentId,
          'firstName': d.guardianFirstName.trim(),
          'lastName': d.guardianLastName.trim(),
          'relationship': d.relationship,
          'isPrimary': true,
        });
        p.guardianAdded = true;
      } on DioException catch (e) {
        return AdmissionFailed('guardian', mapDioError(e));
      }
    }
    return AdmissionDone(p.studentId!);
  }
}
