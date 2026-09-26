/// Notifications (T16 Batch D).
///
/// 🔴 **A notification cannot be opened onto its subject.** `data` is null on
/// every row the live API produces, and there is no target id of any other
/// kind — no complaint id, no invoice id, nothing. So the tap-through a bell
/// implies does not exist, and the screen must not pretend otherwise (D-19).
/// Open item 34.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        category: json['category'] as String? ?? '',
        priority: json['priority'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        // Server-side and persistent, so nothing is tracked on the device.
        readAt: json['readAt'] as String?,
      );

  final String id;
  final String title;
  final String body;
  final String category;
  final String priority;
  final String createdAt;
  final String? readAt;

  bool get isUnread => readAt == null;

  String get categoryLabel => switch (category) {
        'admin' => 'Admin',
        'attendance' => 'Attendance',
        'fee' => 'Fees',
        'exam' => 'Exams',
        'diary' => 'Diary',
        'complaint' => 'Complaints',
        '' => 'Other',
        // Shown as it comes rather than hidden: a category this app has not
        // seen is still a real notification, and dropping it would lose it.
        _ => category,
      };
}

/// Notifications grouped by category, unread first.
///
/// Grouping matters as soon as volume is real: fifty attendance notices
/// must not bury one fee notice. Within a group the unread come first, then
/// newest first — the two things someone opening this is looking for.
class NotificationGroup {
  const NotificationGroup({required this.label, required this.items});

  final String label;
  final List<AppNotification> items;

  int get unreadCount => items.where((n) => n.isUnread).length;
}

List<NotificationGroup> groupNotifications(List<AppNotification> rows) {
  final byCategory = <String, List<AppNotification>>{};
  for (final n in rows) {
    byCategory.putIfAbsent(n.categoryLabel, () => []).add(n);
  }

  final groups = byCategory.entries.map((e) {
    final items = [...e.value]..sort((a, b) {
        if (a.isUnread != b.isUnread) return a.isUnread ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return NotificationGroup(label: e.key, items: items);
  }).toList();

  // Groups with unread first, then alphabetical so the order is stable
  // between loads rather than shuffling as things are read.
  groups.sort((a, b) {
    final byUnread = b.unreadCount.compareTo(a.unreadCount);
    if (byUnread != 0) return byUnread;
    return a.label.compareTo(b.label);
  });
  return groups;
}
