// Web connection seam.
// This is a deliberate in-memory no-op stand-in: it must not import
// dart:ffi or sqlite3 (directly or transitively), since that is what broke
// the web build in the previous project. No schema/tables exist yet, so
// this only needs to satisfy the QueryExecutor contract.
import 'package:drift/drift.dart';

QueryExecutor openConnection() {
  return _NoopWebExecutor();
}

class _NoopWebExecutor extends QueryExecutor {
  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) async =>
      const [];

  @override
  Future<int> runInsert(String statement, List<Object?> args) async => 0;

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async => 0;

  @override
  Future<int> runDelete(String statement, List<Object?> args) async => 0;

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {}

  @override
  Future<void> runBatched(BatchedStatements statements) async {}

  @override
  TransactionExecutor beginTransaction() => _NoopWebTransactionExecutor();

  @override
  QueryExecutor beginExclusive() => this;

  @override
  Future<void> close() async {}
}

class _NoopWebTransactionExecutor extends _NoopWebExecutor
    implements TransactionExecutor {
  @override
  bool get supportsNestedTransactions => false;

  @override
  Future<void> send() async {}

  @override
  Future<void> rollback() async {}
}
