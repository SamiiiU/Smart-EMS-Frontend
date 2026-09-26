import '../../../core/widgets/status_pill.dart';

/// The complaints domain (T16 Batch D).
///
/// ## The privacy model here is ENFORCED, not advisory
///
/// Unlike remarks (T15, open item 23), every rule below was verified with
/// real tokens for each role:
///
/// - a complainant never receives an `is_internal` comment — the server
///   filters them, so the app is not the last line of defence;
/// - a complainant who sends `isInternal: true` has it **downgraded to
///   false** by the server;
/// - an anonymous complaint carries `raised_by_user_id: null` even in the
///   admin's own detail view — the identity is not stored, not merely
///   hidden;
/// - one user cannot read another's complaint (404) or list all (403).
///
/// The app still marks internal comments unmistakably, because staff need to
/// know what the complainant can see — but it is labelling a guarantee, not
/// creating one.

/// The six categories the backend accepts. An unlisted value is a 400 that
/// names the allowed set, so these are exhaustive and verified.
enum ComplaintCategory {
  academic('academic', 'Academic'),
  fee('fee', 'Fees'),
  transport('transport', 'Transport'),
  staffBehaviour('staff_behaviour', 'Staff behaviour'),
  facility('facility', 'Facilities'),
  other('other', 'Something else');

  const ComplaintCategory(this.wire, this.label);

  final String wire;
  final String label;

  static String labelForWire(String? wire) {
    for (final c in ComplaintCategory.values) {
      if (c.wire == wire) return c.label;
    }
    return wire ?? '';
  }
}

/// `low`, `medium`, `high` — `urgent` and `critical` are both rejected.
enum ComplaintPriority {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High');

  const ComplaintPriority(this.wire, this.label);

  final String wire;
  final String label;

  static ComplaintPriority parse(String? raw) {
    for (final p in ComplaintPriority.values) {
      if (p.wire == raw) return p;
    }
    return ComplaintPriority.medium;
  }
}

/// A complaint starts `open` and can move to `in_progress`, `resolved` or
/// `closed`. **`open` cannot be set back** — the backend rejects it — so it
/// is never offered as a choice.
enum ComplaintStatus {
  open('open', 'Open'),
  inProgress('in_progress', 'In progress'),
  resolved('resolved', 'Resolved'),
  closed('closed', 'Closed');

  const ComplaintStatus(this.wire, this.label);

  final String wire;
  final String label;

  static ComplaintStatus parse(String? raw) {
    for (final s in ComplaintStatus.values) {
      if (s.wire == raw) return s;
    }
    return ComplaintStatus.open;
  }

  /// The statuses a staff member can move a complaint TO.
  static List<ComplaintStatus> get settable =>
      [inProgress, resolved, closed];

  bool get isFinished =>
      this == ComplaintStatus.resolved || this == ComplaintStatus.closed;

  AppStatus get pill => switch (this) {
        ComplaintStatus.open => AppStatus.notStarted,
        ComplaintStatus.inProgress => AppStatus.partial,
        ComplaintStatus.resolved => AppStatus.complete,
        ComplaintStatus.closed => AppStatus.inactive,
      };
}

class Complaint {
  const Complaint({
    required this.id,
    required this.subject,
    required this.category,
    required this.priority,
    required this.status,
    required this.isAnonymous,
    required this.createdAt,
    this.description = '',
    this.assignedToStaffId,
    this.raisedByUserId,
    this.dueBy,
    this.resolutionNote,
    this.resolvedAt,
    this.satisfactionRating,
  });

  factory Complaint.fromJson(Map<String, dynamic> json) => Complaint(
        id: json['id'] as String,
        subject: json['subject'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? '',
        priority: ComplaintPriority.parse(json['priority'] as String?),
        status: ComplaintStatus.parse(json['status'] as String?),
        isAnonymous: json['is_anonymous'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        assignedToStaffId: json['assigned_to_staff_id'] as String?,
        // Null for an anonymous complaint, at every role's view — the
        // backend does not store it, so there is nothing to leak.
        raisedByUserId: json['raised_by_user_id'] as String?,
        dueBy: json['due_by'] as String?,
        resolutionNote: json['resolution_note'] as String?,
        resolvedAt: json['resolved_at'] as String?,
        satisfactionRating: json['satisfaction_rating'] as int?,
      );

  final String id;
  final String subject;
  final String description;
  final String category;
  final ComplaintPriority priority;
  final ComplaintStatus status;
  final bool isAnonymous;
  final String createdAt;
  final String? assignedToStaffId;
  final String? raisedByUserId;
  final String? dueBy;
  final String? resolutionNote;
  final String? resolvedAt;
  final int? satisfactionRating;

  String get categoryLabel => ComplaintCategory.labelForWire(category);

  bool get isAssigned => assignedToStaffId != null;

  /// Past its due date and not yet finished.
  bool isOverdue(DateTime today) {
    if (status.isFinished) return false;
    final due = DateTime.tryParse(dueBy ?? '');
    if (due == null) return false;
    return due.isBefore(DateTime(today.year, today.month, today.day));
  }

  int ageInDays(DateTime today) {
    final created = DateTime.tryParse(createdAt);
    if (created == null) return 0;
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(created.year, created.month, created.day))
        .inDays;
    return days < 0 ? 0 : days;
  }
}

/// One entry on the thread.
///
/// [isInternal] is the sharp edge of this screen. The backend guarantees a
/// complainant never receives one; the UI marks them so STAFF know what the
/// complainant can see before they type something they would not say to
/// their face.
class ComplaintComment {
  const ComplaintComment({
    required this.id,
    required this.body,
    required this.isInternal,
    required this.createdAt,
    this.authorUserId,
  });

  factory ComplaintComment.fromJson(Map<String, dynamic> json) =>
      ComplaintComment(
        id: json['id'] as String,
        body: json['body'] as String? ?? '',
        isInternal: json['is_internal'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        authorUserId: json['author_user_id'] as String?,
      );

  final String id;
  final String body;
  final bool isInternal;
  final String createdAt;
  final String? authorUserId;
}

/// D-15 applied to a complaints worklist: ordered by what needs acting on.
///
/// Overdue first, then unassigned, then everything else oldest-first. An
/// admin opens this to decide what to do before lunch, and a list sorted by
/// creation date buries the one that has been sitting for three weeks.
List<Complaint> sortForAdmin(List<Complaint> rows, DateTime today) {
  final sorted = [...rows];
  sorted.sort((a, b) {
    int rank(Complaint c) {
      if (c.status.isFinished) return 3;
      if (c.isOverdue(today)) return 0;
      if (!c.isAssigned) return 1;
      return 2;
    }

    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    // Within a band, the oldest first — it has waited longest.
    return b.ageInDays(today).compareTo(a.ageInDays(today));
  });
  return sorted;
}

/// The complainant's own list: unresolved first, newest first within that.
List<Complaint> sortForOwner(List<Complaint> rows, DateTime today) {
  final sorted = [...rows];
  sorted.sort((a, b) {
    final aDone = a.status.isFinished ? 1 : 0;
    final bDone = b.status.isFinished ? 1 : 0;
    if (aDone != bDone) return aDone.compareTo(bDone);
    return b.ageInDays(today).compareTo(a.ageInDays(today));
  });
  return sorted;
}
