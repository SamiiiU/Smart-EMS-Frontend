// Native (Android/iOS/desktop) connection seam.
//
// PERSISTENT, as of T8. This was `NativeDatabase.memory()` from T0 — correct
// while there were no tables, but a carry-forward hazard ever since
// (DECISIONS.md): an in-memory database loses everything when the process
// ends, and T8's offline attendance queue is exactly the case where that is
// unacceptable. A teacher marking a register in a classroom with no signal
// and then closing the app must not lose it.
//
// `driftDatabase` (drift_flutter) resolves the application documents
// directory itself, so no path_provider wiring is needed here.
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

QueryExecutor openConnection() {
  return driftDatabase(name: 'smart_ems');
}
