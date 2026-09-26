import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/notifications_repository.dart';
import '../domain/notification_models.dart';

/// Screen 5: the notifications centre — and the bell in the app bar finally
/// does something.
///
/// Grouped by category so volume cannot bury the one that matters: fifty
/// attendance notices should not hide a single fee notice. Within a group,
/// unread first.
///
/// 🔴 **Tapping a notification does not go anywhere**, and the screen says
/// so once, plainly. Every row the API produces has `data: null` and carries
/// no id of the thing it is about, so there is nothing to navigate to. A
/// row that looked tappable and did nothing would be worse than one that is
/// honestly inert (D-19). Marking read is a real action and is offered.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.repository, super.key});

  final NotificationsRepository repository;

  @override
  State<NotificationsScreen> createState() => NotificationsScreenState();
}

class NotificationsScreenState extends State<NotificationsScreen> {
  ScreenState<List<AppNotification>> _state =
      const ScreenState<List<AppNotification>>.loading();

  bool _busy = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _state =
        ScreenState<List<AppNotification>>.loading(previous: _state.data));
    try {
      final rows = await widget.repository.load();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<AppNotification>>.data(rows));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<AppNotification>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<void> _markAll() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final marked = await widget.repository.markAllRead();
      if (!mounted) return;
      setState(() {
        _busy = false;
        // The server's own count, not an assumption about what was on screen.
        _notice = marked == 0
            ? 'Nothing was unread.'
            : '$marked ${marked == 1 ? 'notification' : 'notifications'} '
                'marked as read.';
      });
      await load();
    } on LoadFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = f.message ?? 'These could not be marked as read.';
      });
    }
  }

  Future<void> _markOne(AppNotification n) async {
    if (!n.isUnread) return;
    try {
      await widget.repository.markRead(n.id);
      if (mounted) await load();
    } on LoadFailure {
      // Non-blocking: the list is still correct, it just did not change.
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _state.data ?? const <AppNotification>[];
    final unread = rows.where((n) => n.isUnread).length;

    return SetupScaffold(
      title: 'Notifications',
      children: [
        if (_notice != null) ...[
          InlineAlert(tone: InlineAlertTone.info, message: _notice!),
          const SizedBox(height: AppSpacing.space4),
        ],
        if (unread > 0) ...[
          AppButton(
            label: _busy ? 'Marking…' : 'Mark all as read',
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: _busy ? null : _markAll,
          ),
          const SizedBox(height: AppSpacing.space4),
        ],
        // Said once, at the top, rather than on every row.
        const InlineAlert(
          tone: InlineAlertTone.info,
          message: 'These cannot be opened yet — a notification does not '
              'carry a link to the thing it is about, so you will need to '
              'go to that screen yourself.',
        ),
        const SizedBox(height: AppSpacing.space5),
        SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: ScreenStateBuilder<List<AppNotification>>(
            state: _state,
            onRetry: load,
            emptyTitle: 'Nothing here',
            emptyMessage: 'Notifications about attendance, fees, exams and '
                'complaints will appear here.',
            emptyIcon: Icons.notifications_none,
            data: (context, notifications) => ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final group in groupNotifications(notifications)) ...[
                  _GroupHeading(group: group),
                  for (final n in group.items)
                    NotificationRow(
                      notification: n,
                      onMarkRead: () => _markOne(n),
                    ),
                  const SizedBox(height: AppSpacing.space5),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.group});

  final NotificationGroup group;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Wrap(
        spacing: AppSpacing.space3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            group.label,
            style: AppTypography.sectionHeading.copyWith(color: t.textPrimary),
          ),
          if (group.unreadCount > 0)
            Text(
              '${group.unreadCount} unread',
              style: AppTypography.bodyAdminMeta
                  .copyWith(color: t.primaryTextOnSurface),
            ),
        ],
      ),
    );
  }
}

/// One notification.
///
/// Deliberately NOT a tappable row that navigates — there is nowhere to go.
/// The only action is marking it read, and it appears only when there is
/// something to mark.
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    required this.notification,
    required this.onMarkRead,
    super.key,
  });

  final AppNotification notification;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unread = notification.isUnread;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.space3),
      padding: const EdgeInsets.all(AppSpacing.space5),
      constraints: const BoxConstraints(minHeight: AppSizing.listRowMinHeight),
      decoration: BoxDecoration(
        // Unread carries weight as well as tint, so it does not rely on
        // colour alone to be findable.
        color: unread ? t.surface : t.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: unread ? t.primaryAccent : t.border,
          width: AppSizing.borderThin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.space3,
            runSpacing: AppSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                notification.title,
                style: (unread
                        ? AppTypography.personName
                        : AppTypography.bodyAdminMeta)
                    .copyWith(color: t.textPrimary),
              ),
              if (unread)
                Text(
                  'Unread',
                  style: AppTypography.overline
                      .copyWith(color: t.primaryTextOnSurface),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            notification.body,
            style: AppTypography.bodyAdminMeta.copyWith(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space2),
          Row(
            children: [
              Expanded(
                child: Text(
                  notification.createdAt,
                  style: AppTypography.timestamp
                      .copyWith(color: t.textSecondary),
                ),
              ),
              if (unread)
                AppButton(
                  label: 'Mark read',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: onMarkRead,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
