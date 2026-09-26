import 'package:flutter/foundation.dart';

/// Which group of people the admin is looking at.
enum PeopleGroup {
  staff('Staff'),
  students('Students'),
  parents('Parents');

  const PeopleGroup(this.label);

  final String label;
}

/// One person, as the admin's accounts list shows them.
///
/// Deliberately flat and role-agnostic: staff, students and guardians come
/// from three different endpoints with three different shapes, and the list
/// needs one row type. Whatever the source, the two questions the admin has
/// are the same — who is this, and can they sign in?
@immutable
class PersonAccount {
  const PersonAccount({
    required this.id,
    required this.fullName,
    required this.group,
    this.identifier,
    this.detail,
    this.userId,
  });

  final String id;
  final String fullName;
  final PeopleGroup group;

  /// Employee code / admission number. Null for guardians, who have neither.
  final String? identifier;

  /// Secondary line: designation, class, or "father of Ali Khan".
  final String? detail;

  /// The login this record is linked to, or null when there is none.
  ///
  /// 🔴 This is the ONLY thing that tells "account exists" from "account
  /// does not exist". The backend has **no endpoint that lists logins**
  /// (`GET /api/users` does not exist — verified live 2026-09-23), so a
  /// login created without being linked to a person record is invisible to
  /// this screen. That orphan case is exactly what the create-user wizard's
  /// recovery path (D-17) exists to prevent.
  final String? userId;

  bool get hasLogin => userId != null && userId!.isNotEmpty;

  /// Client-side filter (B-02: the API ignores `q`/`search`).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        (identifier?.toLowerCase().contains(q) ?? false) ||
        (detail?.toLowerCase().contains(q) ?? false);
  }
}

/// Everything the accounts screen renders, per group.
@immutable
class PeopleDirectory {
  const PeopleDirectory({
    required this.staff,
    required this.students,
    required this.parents,
    this.parentsPartial = false,
  });

  final List<PersonAccount> staff;
  final List<PersonAccount> students;
  final List<PersonAccount> parents;

  /// True when one or more per-student guardian lookups failed.
  ///
  /// The parents list is assembled student by student (there is no list
  /// endpoint), so a partial failure is possible in a way it is not for the
  /// other two groups. Shown as a warning ON the list rather than replacing
  /// it with an error: the parents that WERE loaded are real, and hiding
  /// them would be worse than saying the list is incomplete.
  final bool parentsPartial;

  List<PersonAccount> of(PeopleGroup group) => switch (group) {
        PeopleGroup.staff => staff,
        PeopleGroup.students => students,
        PeopleGroup.parents => parents,
      };

  bool get isEmpty =>
      staff.isEmpty && students.isEmpty && parents.isEmpty;

  int get withoutLogin =>
      [...staff, ...students, ...parents].where((p) => !p.hasLogin).length;
}
