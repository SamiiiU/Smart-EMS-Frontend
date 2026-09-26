import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/scales.dart';
import '../../../core/theme/sizing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../data/auth_repository.dart';

/// The sign-in screen. Three fields, because the API requires three:
/// `institutionCode`, `username`, `password` (confirmed against the live
/// `/auth/login` schema — all three are `required`).
///
/// **There is deliberately no "create account" affordance.** The backend
/// exposes no self-signup endpoint; accounts are provisioned by an
/// institution admin (`POST /api/users/provision`, which itself requires an
/// admin token). Offering a signup link would be a false affordance (D-19) —
/// a button that cannot lead anywhere. Instead the screen says plainly where
/// accounts come from, which is the same reasoning as
/// `UnlinkedProfileState`: when the user cannot self-serve, point at who can.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.repository,
    required this.onSignedIn,
    this.onForcePasswordChange,
    super.key,
  });

  final AuthRepository repository;

  /// Called INSTEAD of [onSignedIn] when the backend reports
  /// `forcePasswordChange`. Kept separate so this screen never has to know
  /// what the app does about it — it only reports which of the two
  /// happened.
  final VoidCallback? onForcePasswordChange;

  /// Called after tokens are persisted. The caller swaps in `AppShell`,
  /// which runs its own `/me` identity gate before any tab renders (T5).
  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  String _institutionCode = '';
  String _username = '';
  String _password = '';
  bool _submitting = false;
  String? _errorMessage;

  /// Password visibility. Starts hidden — revealing is the deliberate act.
  bool _passwordVisible = false;

  final _institutionFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// Measured so the flight lands EXACTLY on the real heading at every
  /// width and text scale. A hard-coded offset would drift at 360px or
  /// under a large text scale and the hand-off would visibly jump.
  final _stackKey = GlobalKey();
  final _headingKey = GlobalKey();

  late final AnimationController _intro;
  late final Animation<double> _flight;
  late final Animation<double> _welcomeIn;
  late final Animation<double> _welcomeOut;
  late final Animation<double> _wordmarkIn;

  bool _configured = false;

  /// Null until measured, or when the intro is skipped. While null the
  /// overlay is not drawn at all.
  Rect? _headingRect;
  double _startScale = 1;

  bool get _canSubmit =>
      !_submitting &&
      _institutionCode.trim().isNotEmpty &&
      _username.trim().isNotEmpty &&
      _password.isNotEmpty;

  /// The wordmark has landed; the real heading takes over from here.
  bool get _handedOver => _flight.value >= 1;

  @override
  void initState() {
    super.initState();
    // Created ONCE and started once. Nothing on the error path touches it,
    // so a failed sign-in re-renders the form without replaying the intro.
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _Timing.totalMs),
    );

    _welcomeIn = CurvedAnimation(
      parent: _intro,
      curve: Interval(
        _Timing.f(_Timing.welcomeInStart),
        _Timing.f(_Timing.welcomeInEnd),
        curve: Curves.easeOut,
      ),
    );
    _wordmarkIn = CurvedAnimation(
      parent: _intro,
      curve: Interval(
        _Timing.f(_Timing.wordmarkInStart),
        _Timing.f(_Timing.wordmarkInEnd),
        curve: Curves.easeOut,
      ),
    );
    _welcomeOut = CurvedAnimation(
      parent: _intro,
      curve: Interval(
        _Timing.f(_Timing.welcomeOutStart),
        _Timing.f(_Timing.welcomeOutEnd),
        curve: Curves.easeIn,
      ),
    );
    _flight = CurvedAnimation(
      parent: _intro,
      // easeInOutCubic: eases out of the hold and settles into place, rather
      // than snapping into motion or arriving at speed.
      curve: Interval(
        _Timing.f(_Timing.flightStart),
        _Timing.f(_Timing.flightEnd),
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) return;
    _configured = true;

    // Reduced motion plays NONE of it (D-29) — not a faster version. Jump
    // to the settled end state and never measure or draw the overlay.
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      return;
    }

    // Measure AFTER first layout, then fly. Starting before the target is
    // known would mean guessing where to land.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
      _intro.forward();
    });
  }

  void _measure() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final headingBox =
        _headingKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || headingBox == null || !headingBox.hasSize) return;

    final topLeft = headingBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final rect = topLeft & headingBox.size;

    // Big enough to read as a splash, but clamped so it can never exceed
    // the viewport on a 360px phone or at a large text scale.
    final maxScale = headingBox.size.width == 0
        ? 1.0
        : (stackBox.size.width * 0.86) / headingBox.size.width;

    setState(() {
      _headingRect = rect;
      _startScale = math.max(1, math.min(2.2, maxScale));
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _institutionFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final outcome = await widget.repository.login(
      institutionCode: _institutionCode.trim(),
      username: _username.trim(),
      password: _password,
    );

    if (!mounted) return;

    switch (outcome) {
      case LoginSucceeded(:final forcePasswordChange):
        setState(() => _submitting = false);
        final forced = widget.onForcePasswordChange;
        if (forcePasswordChange && forced != null) {
          forced();
        } else {
          widget.onSignedIn();
        }
      case LoginFailed(:final failure):
        setState(() {
          _submitting = false;
          // The backend's own message, verbatim — "Invalid credentials"
          // for a bad password (verified live). Never a generic string.
          _errorMessage = failure.message ?? 'Sign in failed.';
        });
    }
  }

  AppTextFieldState get _fieldState =>
      _submitting ? AppTextFieldState.disabled : AppTextFieldState.normal;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.page,
      body: SafeArea(
        child: Stack(
          key: _stackKey,
          children: [
            // The real form, laid out normally from the very first frame.
            // Nothing here animates layout, so the fields are focusable and
            // tappable throughout the intro.
            Center(
              // Scrollable so the form still reaches the submit button at
              // large text scales and on short viewports with the keyboard
              // open.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.space8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSizing.authFormMaxWidth,
                  ),
                  child: _form(context),
                ),
              ),
            ),

            // The flying wordmark. Drawn only while it is in transit, and
            // never hit-testable — it must not swallow a tap meant for the
            // field beneath it.
            // Presence is driven from INSIDE the overlay's own
            // AnimatedBuilder — a condition here would never be re-evaluated,
            // since this build does not listen to the controller.
            if (_headingRect != null)
              IgnorePointer(child: _FlightOverlay(
                intro: _intro,
                flight: _flight,
                welcomeIn: _welcomeIn,
                welcomeOut: _welcomeOut,
                wordmarkIn: _wordmarkIn,
                headingRect: _headingRect!,
                startScale: _startScale,
                stackSize: (_stackKey.currentContext?.findRenderObject()
                        as RenderBox?)
                    ?.size,
              )),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tightly wrapped so the measured rect is the GLYPH box, not the
        // full column width — the overlay is centred on the glyphs, and a
        // stretched box would land the hand-off off-centre.
        Align(
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _flight,
            builder: (context, child) => Opacity(
              // Hidden until the wordmark lands on it. Both are the same
              // style at the same place, so the swap is invisible.
              opacity: _handedOver ? 1 : 0,
              child: child,
            ),
            child: Text(
              'Smart EMS',
              key: _headingKey,
              style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        _Reveal(
          intro: _intro,
          beginMs: _Timing.subtitleStart,
          child: Text(
            'Sign in to your institution',
            style: AppTypography.bodyAdminMeta.copyWith(
              color: t.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // NOT wrapped in _Reveal: an error appears long after the intro and
        // must never be tied to it.
        if (_errorMessage != null) ...[
          InlineAlert(
            tone: InlineAlertTone.danger,
            message: _errorMessage!,
          ),
          const SizedBox(height: AppSpacing.space6),
        ],

        _Reveal(
          intro: _intro,
          beginMs: _Timing.field1Start,
          child: AppTextField(
            label: 'Institution code',
            value: _institutionCode,
            placeholder: 'e.g. test-school',
            state: _fieldState,
            focusNode: _institutionFocus,
            // Straight into typing — one less tap every morning.
            autofocus: true,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _usernameFocus.requestFocus(),
            onChanged: (v) => setState(() => _institutionCode = v),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),

        _Reveal(
          intro: _intro,
          beginMs: _Timing.field2Start,
          child: AppTextField(
            label: 'Username',
            value: _username,
            state: _fieldState,
            focusNode: _usernameFocus,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            onChanged: (v) => setState(() => _username = v),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),

        _Reveal(
          intro: _intro,
          beginMs: _Timing.field3Start,
          child: AppTextField(
            label: 'Password',
            value: _password,
            obscure: !_passwordVisible,
            state: _fieldState,
            focusNode: _passwordFocus,
            textInputAction: TextInputAction.done,
            // Enter on the last field submits, rather than doing nothing and
            // leaving the user hunting for the button.
            onSubmitted: (_) => submit(),
            onChanged: (v) => setState(() => _password = v),
            trailing: _PasswordToggle(
              visible: _passwordVisible,
              enabled: !_submitting,
              onToggle: () => setState(
                () => _passwordVisible = !_passwordVisible,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        _Reveal(
          intro: _intro,
          beginMs: _Timing.tailStart,
          child: AppButton(
            label: _submitting ? 'Signing in…' : 'Sign in',
            fullWidth: true,
            // Null while submitting or incomplete: AppButton renders its own
            // disabled treatment, so there is no second, competing
            // "disabled" style invented here.
            onPressed: _canSubmit ? submit : null,
          ),
        ),
        const SizedBox(height: AppSpacing.space8),

        // NOT a link. See the class doc — there is no self-signup endpoint,
        // so anything tappable here would be a promise the backend cannot
        // keep (D-19).
        _Reveal(
          intro: _intro,
          beginMs: _Timing.tailStart,
          child: Text(
            'Accounts are created by your institution’s administrator. '
            'If you do not have one, contact them to be added.',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: t.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// The intro's choreography, in MILLISECONDS.
///
/// Kept as real times rather than 0–1 fractions because the sequence is
/// tuned by feel: "hold for a second" is a statement about time, and
/// expressing it as `0.607` would make the next adjustment guesswork.
/// [f] converts to the fractions `Interval` wants.
abstract final class _Timing {
  static const int totalMs = 2800;

  /// Phase 1 — the wordmark introduces itself, centred.
  static const int welcomeInStart = 0;
  static const int welcomeInEnd = 350;
  static const int wordmarkInStart = 250;
  static const int wordmarkInEnd = 700;

  /// Phase 2 — a deliberate HOLD from 700ms to 1700ms. Nothing moves for a
  /// full second, so the wordmark registers before it goes anywhere. This
  /// gap is the animation, as much as the motion around it.
  static const int flightStart = 1700;
  static const int flightEnd = 2250;

  /// "Welcome to" leaves just before the flight begins, so the wordmark
  /// departs alone rather than dragging a label with it.
  static const int welcomeOutStart = 1500;
  static const int welcomeOutEnd = 1750;

  /// Phase 3 — the form arrives, ~100ms apart.
  static const int subtitleStart = 2250;
  static const int field1Start = 2350;
  static const int field2Start = 2450;
  static const int field3Start = 2550;
  static const int tailStart = 2600;

  /// How long one element takes to fade and rise into place.
  static const int revealSpan = 200;

  static double f(int ms) => (ms / totalMs).clamp(0.0, 1.0);
}

/// The centre-to-heading flight.
///
/// A real positional flight, measured rather than approximated: the wordmark
/// starts centred at [startScale] and lands exactly on [headingRect], where
/// the identically-styled real heading takes over. Because both are the same
/// text in the same style at the same position at hand-off, the swap is
/// invisible.
///
/// Driven by [AnimatedBuilder] with a cached `child`, so the two `Text`
/// widgets are built ONCE and only the transform/opacity repaint per frame.
class _FlightOverlay extends StatelessWidget {
  const _FlightOverlay({
    required this.intro,
    required this.flight,
    required this.welcomeIn,
    required this.welcomeOut,
    required this.wordmarkIn,
    required this.headingRect,
    required this.startScale,
    required this.stackSize,
  });

  final Animation<double> intro;
  final Animation<double> flight;
  final Animation<double> welcomeIn;
  final Animation<double> welcomeOut;
  final Animation<double> wordmarkIn;
  final Rect headingRect;
  final double startScale;
  final Size? stackSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = stackSize;
    if (size == null) return const SizedBox.shrink();

    final startCentre = Offset(size.width / 2, size.height / 2);
    final endCentre = headingRect.center;

    return AnimatedBuilder(
      animation: intro,
      builder: (context, child) {
        final progress = flight.value;
        // Torn down the moment it lands: the identically-styled real
        // heading has taken over, and leaving a second copy in the tree
        // would be dead weight painted on every later frame.
        if (progress >= 1) return const SizedBox.shrink();
        final centre = Offset.lerp(startCentre, endCentre, progress)!;
        final scale = _lerp(startScale, 1, progress);
        final welcomeOpacity =
            (welcomeIn.value * (1 - welcomeOut.value)).clamp(0.0, 1.0);

        return Stack(
          children: [
            // "Welcome to", sitting above the wordmark while it is centred
            // and fading out as the flight begins.
            if (welcomeOpacity > 0)
              Positioned(
                left: 0,
                right: 0,
                top: startCentre.dy -
                    headingRect.height * startScale -
                    AppSpacing.space6,
                child: Opacity(
                  opacity: welcomeOpacity,
                  child: Text(
                    'Welcome to',
                    textAlign: TextAlign.center,
                    style: AppTypography.sectionHeading.copyWith(
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: centre.dx - headingRect.width / 2,
              top: centre.dy - headingRect.height / 2,
              width: headingRect.width,
              height: headingRect.height,
              child: Opacity(
                opacity: wordmarkIn.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      // Built once, never rebuilt during the flight.
      child: Text(
        'Smart EMS',
        style: AppTypography.screenTitle.copyWith(color: t.textPrimary),
      ),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Fade + slight rise for one staggered element.
///
/// Uses [FadeTransition] and [SlideTransition] rather than an
/// `AnimatedBuilder` around `Opacity`/`Transform`: both animate at the
/// RENDER OBJECT level, so the subtree is never rebuilt during the intro —
/// only repainted. `Opacity` would also force a `saveLayer` on every frame
/// it sits between 0 and 1.
///
/// Only paint-level properties animate, so the child keeps its real size and
/// position in the layout from the first frame. That is what lets the fields
/// be focusable and tappable while the intro is still running.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.intro,
    required this.beginMs,
    required this.child,
  });

  final Animation<double> intro;

  /// When this element starts arriving, in milliseconds into the intro.
  final int beginMs;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: intro,
      curve: Interval(
        _Timing.f(beginMs),
        _Timing.f(beginMs + _Timing.revealSpan),
        curve: Curves.easeOut,
      ),
    );

    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        // Fractional: a quarter of the element's own height, so the rise
        // scales with text size instead of being a fixed pixel nudge.
        position: Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }
}

/// Eye toggle for the password field.
///
/// The SEMANTIC label changes with the state, not just the glyph — a screen
/// reader user needs to know what the control will do, and "eye icon" does
/// not tell them whether the password is currently shown.
class _PasswordToggle extends StatelessWidget {
  const _PasswordToggle({
    required this.visible,
    required this.enabled,
    required this.onToggle,
  });

  final bool visible;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Semantics(
      button: true,
      enabled: enabled,
      label: visible ? 'Hide password' : 'Show password',
      child: GestureDetector(
        onTap: enabled ? onToggle : null,
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: AppSpacing.space7,
            color: enabled ? t.textSecondary : t.textDisabled,
          ),
        ),
      ),
    );
  }
}
