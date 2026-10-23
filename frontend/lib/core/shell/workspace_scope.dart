import 'package:flutter/widgets.dart';

/// Lets More offer "switch workspace" (ADR-011) without threading a callback
/// through every role's destination builder. Absent when the account has
/// only one workspace.
class WorkspaceScope extends InheritedWidget {
  const WorkspaceScope({
    required this.switchLabel,
    required this.onSwitch,
    required super.child,
    super.key,
  });

  /// e.g. "Switch to personal workspace".
  final String switchLabel;
  final Future<void> Function() onSwitch;

  static WorkspaceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceScope>();

  @override
  bool updateShouldNotify(WorkspaceScope oldWidget) =>
      switchLabel != oldWidget.switchLabel;
}
