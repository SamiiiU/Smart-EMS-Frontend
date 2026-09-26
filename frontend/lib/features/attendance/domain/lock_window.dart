import 'package:flutter/foundation.dart';

/// Whether a register is still editable.
///
/// **The window is 0 in production today.** That is treated as a real value
/// meaning "no grace period beyond the attendance date itself" — NOT as a
/// special case to branch around. There is deliberately no `if (window ==
/// zero)` anywhere: when Ali sets a real number, the same arithmetic starts
/// granting real extra time with no frontend change.
///
/// It is also NOT faked to a non-zero value for testing convenience. Tests
/// pass an explicit window, which is how a caller will supply the real one.
@immutable
class LockWindow {
  const LockWindow(this.duration);

  /// Production value today. Not a placeholder — the actual configured one.
  const LockWindow.immediate() : duration = Duration.zero;

  final Duration duration;

  /// A register for [attendanceDate] stays open until the end of that day
  /// plus [duration].
  bool isOpen({required DateTime attendanceDate, required DateTime now}) {
    final endOfDay = DateTime(
      attendanceDate.year,
      attendanceDate.month,
      attendanceDate.day,
      23,
      59,
      59,
    );
    return !now.isAfter(endOfDay.add(duration));
  }

  /// Explains WHY a locked register is locked. A disabled control with no
  /// explanation is the failure mode this exists to avoid — a teacher who
  /// cannot mark attendance needs to know it is a policy, not a bug, and
  /// who can help.
  String lockedReason({required DateTime attendanceDate}) {
    if (duration == Duration.zero) {
      return 'Attendance for this date closed at the end of the day. '
          'Your institution allows no editing window afterwards. '
          'Ask an administrator to make a correction.';
    }
    return 'Attendance for this date closed '
        '${_humanize(duration)} after the end of the day. '
        'Ask an administrator to make a correction.';
  }

  static String _humanize(Duration d) {
    if (d.inDays >= 1) {
      return '${d.inDays} ${d.inDays == 1 ? 'day' : 'days'}';
    }
    if (d.inHours >= 1) {
      return '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'}';
    }
    return '${d.inMinutes} minutes';
  }
}
