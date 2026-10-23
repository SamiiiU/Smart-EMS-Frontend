import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/shell/mobile_app_bar.dart';
import 'package:smartems/core/shell/sync_status.dart';
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/app_text_field.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

/// F6: the shared form field gives screen readers a name, a required hint and an
/// announced validation error, without swallowing the trailing action button.
void main() {
  testWidgets('field is named by its label and announces required', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const AppTextField(label: 'Mailbox email', required: true)));
    final node = tester.getSemantics(find.byType(EditableText));
    expect(node.label, 'Mailbox email');
    expect(node.hint, 'Required');
    expect(node, isSemantics(isTextField: true));
    expect(find.bySemanticsLabel('Mailbox email'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('validation error is announced as a live region and joins the hint', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const AppTextField(
      label: 'Authenticator code',
      required: true,
      state: AppTextFieldState.error,
      errorText: 'Enter the 6-digit code',
    )));
    expect(tester.getSemantics(find.byType(EditableText)).hint, 'Required. Enter the 6-digit code');
    final error = tester.getSemantics(find.text('Enter the 6-digit code'));
    expect(error, isSemantics(isLiveRegion: true));
    handle.dispose();
  });

  testWidgets('optional field has no required hint; trailing button stays its own action', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(AppTextField(
      label: 'Password',
      obscure: true,
      trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.visibility), tooltip: 'Show password'),
    )));
    final field = tester.getSemantics(find.byType(EditableText));
    expect(field.label, 'Password');
    expect(field.hint, isEmpty);
    expect(field, isSemantics(isObscured: true));
    final button = tester.getSemantics(find.byType(IconButton));
    expect(button, isSemantics(isButton: true));
    expect(identical(button, field), isFalse);
    handle.dispose();
  });

  testWidgets('keyboard Tab moves focus field to field', (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      AppTextField(label: 'First name', autofocus: true),
      AppTextField(label: 'Last name'),
    ])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ayesha');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus;
    final second = tester.widget<TextField>(find.byType(TextField).at(1)).focusNode;
    expect(focused, same(second));
  });

  testWidgets('button is named once and is activatable by assistive technology', (tester) async {
    final handle = tester.ensureSemantics();
    var pressed = 0;
    await tester.pumpWidget(_host(AppButton(label: 'Sign in', onPressed: () => pressed++)));
    final node = tester.getSemantics(find.byType(AppButton));
    expect(node.label, 'Sign in');
    expect(node, isSemantics(isButton: true, hasTapAction: true, isEnabled: true));
    tester.semantics.tap(find.semantics.byLabel('Sign in'));
    await tester.pump();
    expect(pressed, 1);
    await tester.pumpWidget(_host(const AppButton(label: 'Sign in')));
    expect(tester.getSemantics(find.byType(AppButton)), isSemantics(isButton: true, isEnabled: false));
    handle.dispose();
  });

  testWidgets('F17: the navigation menu button is announced exactly once', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(appBar: MobileAppBar(
        institutionName: 'Rehearsal Academy North',
        syncStatus: const SyncStatus.synced(),
        onMenuTap: () {},
      )),
    ));
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
    expect(find.bySemanticsLabel('Open navigation menu'), findsNothing, reason: 'no second, separately labelled node');
    handle.dispose();
  });
}
