// Native (Android/iOS/desktop) connection seam.
// Uses drift's sqlite3-backed NativeDatabase, which is safe here because
// this file is never imported on the web target.
import 'package:drift/native.dart';
import 'package:drift/drift.dart';

QueryExecutor openConnection() {
  return NativeDatabase.memory();
}
