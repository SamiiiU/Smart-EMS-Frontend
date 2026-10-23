import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/scales.dart';
import '../theme/typography.dart';
import '../widgets/app_button.dart';

/// F12: shown at startup when a stored session exists but the server cannot be
/// reached. Nothing is erased: the session and any attendance saved offline stay
/// on this device.
///
/// Hard-QA BUG-QA-16: it used to wait for the user to press Try again, even
/// after the connection had come back (Pixel: still offline 45 s after the
/// server was reachable). It now retries ON ITS OWN:
/// - on a bounded, growing interval (5 s, 10 s, 20 s, 40 s, then every 60 s),
///   because losing the server does not always change the device's own
///   connectivity (a server outage, a captive network, a USB tunnel);
/// - immediately when the app returns to the foreground.
/// Only one attempt runs at a time. [onRetry] is the normal sign-in completion:
/// success leaves this screen, and an expired or revoked session is sent to
/// sign-in there, so bad credentials are never retried here in a loop.
class OfflineRestoreScreen extends StatefulWidget {
  const OfflineRestoreScreen({
    required this.onRetry,
    this.backoff = defaultBackoff,
    this.serverBusy = false,
    super.key,
  });

  final Future<void> Function() onRetry;

  /// The server answered but is rate limiting (429): say "busy", not
  /// "offline". Retry behaviour is unchanged.
  final bool serverBusy;

  /// Delays between automatic attempts; the last one repeats.
  final List<Duration> backoff;

  static const defaultBackoff = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 60),
  ];

  @override
  State<OfflineRestoreScreen> createState() => _OfflineRestoreScreenState();
}

class _OfflineRestoreScreenState extends State<OfflineRestoreScreen>
    with WidgetsBindingObserver {
  bool _retrying = false;
  int _attempt = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Returning to the app is the most likely moment the network is back.
      _attempt = 0;
      _retry();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final delays = widget.backoff;
    if (delays.isEmpty) return;
    final delay =
        delays[_attempt < delays.length ? _attempt : delays.length - 1];
    _timer = Timer(delay, () {
      _attempt++;
      _retry();
    });
  }

  Future<void> _retry() async {
    if (_retrying || !mounted) return; // single flight
    _timer?.cancel();
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } on Object {
      // Still unreachable: stay here and try again later.
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
        _schedule();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      widget.serverBusy ? 'Server busy' : "You're offline",
                      style: AppTypography.screenTitle.copyWith(
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  Text(
                    widget.serverBusy
                        ? 'Smart EMS is receiving too many requests right now. You are still '
                              'signed in, and any attendance you saved offline is kept safely on '
                              'this device. It will sync once the server catches up.'
                        : 'Smart EMS could not reach the server. You are still signed in, and any '
                              'attendance you saved offline is kept safely on this device. It will '
                              'sync when the connection returns.',
                    style: AppTypography.bodyTeacher.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _retrying
                          ? 'Connecting…'
                          : widget.serverBusy
                          ? 'Retrying automatically. You do not need to do anything.'
                          : 'Reconnecting automatically. You do not need to do anything.',
                      key: const Key('offline-auto-status'),
                      style: AppTypography.bodyAdminMeta.copyWith(
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  AppButton(
                    key: const Key('offline-retry'),
                    label: _retrying ? 'Connecting…' : 'Try again now',
                    fullWidth: true,
                    onPressed: _retrying
                        ? null
                        : () {
                            _attempt = 0;
                            _retry();
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
