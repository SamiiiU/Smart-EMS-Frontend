import '../domain/attendance_models.dart';
import 'package:flutter/material.dart';
import '../data/attendance_queue.dart';

/// Keep is the default. Only the explicitly confirmed snapshot is discarded.
Future<bool> confirmAttendanceSignOut(
  BuildContext context,
  AttendanceQueue queue,
) async {
  final owner = queue.scopeIdentity;
  late final List<AttendanceMark> pending;
  try {
    pending = await queue.pending();
  } catch (_) {
    if (!context.mounted || queue.scopeIdentity != owner) return false;
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saved attendance unavailable'),
        content: const Text(
          'Saved marks could not be read. Signing out will keep the stored data on this device. Do not clear app data; retry with the same account or contact support.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keep data and sign out'),
          ),
        ],
      ),
    );
    return keep == true && queue.scopeIdentity == owner;
  }
  if (pending.isEmpty) return true;
  if (!context.mounted) return false;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pending attendance'),
      content: Text(
        '${pending.length} attendance marks have not synced. Keep them on this device and sign in with the same account to sync later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'discard'),
          child: const Text('Discard marks'),
        ),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, 'keep'),
          child: const Text('Keep and sign out'),
        ),
      ],
    ),
  );
  if (choice == null || queue.scopeIdentity != owner) return false;
  if (choice == 'keep') return true;
  if (!context.mounted) return false;
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard unsynced marks?'),
      content: Text(
        'The ${pending.length} pending marks shown above will be removed from this device. This cannot be undone.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep marks'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Discard and sign out'),
        ),
      ],
    ),
  );
  if (discard != true || queue.scopeIdentity != owner) return false;
  await queue.remove(pending.map((mark) => mark.clientUuid));
  return queue.scopeIdentity == owner;
}
