import 'dart:convert';
import 'dart:math';
import 'payment_intent_store.dart';

import 'package:dio/dio.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../domain/finance_models.dart';
import '../domain/money.dart';

/// Every fee call the app makes (T14 Batch B).
///
/// 🔴 **All reads go through [_json], which asks dio for the RAW TEXT and
/// quotes the money literals before decoding.** That is the whole reason no
/// amount in this app ever passes through a `double`: `jsonDecode` would
/// otherwise turn `5500.00` into a binary float before any of our code could
/// object. Adding a read that calls `dio.get` directly would silently break
/// that guarantee, which is why there is exactly one door.
///
/// Failures throw [LoadFailure], as elsewhere — except [recordPayment] and
/// [approvePayment], which return a typed message, because "that is more
/// than is outstanding" is an ordinary answer at a fee counter, not an error
/// state that should blank the screen.
class FinanceRepository {
  FinanceRepository(
    this.dio, {
    this.newIdempotencyKey = _uuidV4,
    PaymentIntentStore? intents,
    String? Function()? owner,
  }) : _intents = intents ?? MemoryPaymentIntentStore(),
       _owner = owner ?? (() => 'test-local'),
       _pinOwner = owner != null;
  final PaymentIntentStore _intents;
  final String? Function() _owner;
  final bool _pinOwner;
  Future<void> _paymentTail = Future.value();

  final Dio dio;

  /// Injected so a test can pin the key. Every payment needs a fresh UUID —
  /// the backend rejects anything that is not one, with the unhelpful
  /// message "Malformed request body".
  final String Function() newIdempotencyKey;

  // --- The single decoding door ---------------------------------------------

  static final Options _plain = Options(responseType: ResponseType.plain);

  Future<Object?> _json(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final raw = res.data;
      if (raw == null) return null;
      final text = raw is String ? raw : raw.toString();
      if (text.isEmpty) return null;
      return jsonDecode(FinanceJson.quoteMoney(text));
    } on DioException catch (err) {
      throw mapDioError(_decodeErrorBody(err));
    }
  }

  Future<List<Map<String, dynamic>>> _array(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    final body = await _json(
      () => dio.get<dynamic>(path, queryParameters: query, options: _plain),
    );
    return (body as List? ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _object(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    final body = await _json(
      () => dio.get<dynamic>(path, queryParameters: query, options: _plain),
    );
    return (body as Map?)?.cast<String, dynamic>() ?? const {};
  }

  // --- Fee heads -------------------------------------------------------------

  Future<List<FeeHead>> loadHeads() async {
    final rows = await _array('/api/fee/heads');
    return rows.map(FeeHead.fromJson).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<FeeHead> createHead({
    required String name,
    required bool isRecurring,
    String taxRate = '0',
  }) async {
    final body = await _json(
      () => dio.post<dynamic>(
        '/api/fee/heads',
        data: {'name': name, 'isRecurring': isRecurring, 'taxRate': taxRate},
        options: _plain,
      ),
    );
    return FeeHead.fromJson((body as Map).cast<String, dynamic>());
  }

  // --- Fee plans -------------------------------------------------------------

  /// List rows carry no `items` and no total — `?classId=` is ignored by
  /// this endpoint, so no filter is sent that would not be honoured.
  Future<List<FeePlan>> loadPlans() async {
    final rows = await _array('/api/fee/plans');
    return rows.map(FeePlan.fromJson).toList();
  }

  /// The only call that returns a plan's items and its server-side total.
  Future<FeePlan> loadPlan(String id) async =>
      FeePlan.fromJson(await _object('/api/fee/plans/$id'));

  /// `academicYearId` is always passed explicitly.
  ///
  /// The backend's `current` flag points at an EXPIRED year on live data
  /// (verified in T13 and again here), so anything that let the server pick
  /// the year would quietly bill against last year.
  Future<FeePlan> createPlan({
    required String name,
    required String frequency,
    required String classId,
    required String academicYearId,
    required String campusId,
    required int dueDay,
    required int graceDays,
    required List<({String feeHeadId, Money amount})> items,
  }) async {
    final body = await _json(
      () => dio.post<dynamic>(
        '/api/fee/plans',
        data: {
          'name': name,
          'frequency': frequency,
          'classId': classId,
          'academicYearId': academicYearId,
          'campusId': campusId,
          'dueDay': dueDay,
          'graceDays': graceDays,
          'items': [
            for (final item in items)
              {
                'feeHeadId': item.feeHeadId,
                // Sent as the exact decimal string, never as a double.
                'amount': item.amount.toBackendString(),
              },
          ],
        },
        options: _plain,
      ),
    );
    return FeePlan.fromJson((body as Map).cast<String, dynamic>());
  }

  /// Bulk generation. Idempotent per period — a repeat run reports the
  /// invoices as `skipped` rather than duplicating them (verified live).
  Future<GenerationResult> generate({
    required String planId,
    required String period,
  }) async {
    final body = await _json(
      () => dio.post<dynamic>(
        '/api/fee/plans/$planId/generate',
        data: {'period': period},
        options: _plain,
      ),
    );
    return GenerationResult.fromJson((body as Map).cast<String, dynamic>());
  }

  Future<Map<String, dynamic>> loadWorkflow(
    String id,
    CancelToken token,
  ) async {
    final body = await _json(
      () => dio.get<dynamic>(
        '/api/workflow-jobs/$id',
        options: _plain,
        cancelToken: token,
      ),
    );
    return (body as Map).cast<String, dynamic>();
  }

  // --- Invoices --------------------------------------------------------------

  /// Only the three filters this endpoint honours are sent. `?sectionId=` is
  /// IGNORED by the backend (bogus-id control returned the row anyway), so
  /// the screen offers no section filter — an inert control is a lie.
  Future<InvoicePage> loadInvoices({
    String? classId,
    String? status,
    String? period,
    int page = 0,
    int size = 50,
  }) async {
    final body = await _object('/api/fee/invoices', {
      'classId': ?classId,
      'status': ?status,
      'period': ?period,
      'page': page,
      'size': size,
    });
    return InvoicePage(
      invoices: (body['content'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Invoice.fromJson)
          .toList(),
      totalElements: body['totalElements'] as int? ?? 0,
    );
  }

  /// The only call that carries an invoice's lines.
  Future<Invoice> loadInvoice(String id) async =>
      Invoice.fromJson(await _object('/api/fee/invoices/$id'));

  // --- Payments --------------------------------------------------------------

  /// Records a payment. It lands `pending_approval`: the money is NOT on the
  /// invoice until someone approves it, and the screen says so.
  ///
  /// Returns the payment id, or a message to show. The message is the
  /// backend's own where it has one — "Amount 999999.99 exceeds outstanding
  /// balance 5499.00" tells the clerk exactly what to do, and nothing this
  /// app could write would be better.
  Future<T> _serializePayment<T>(Future<T> Function() action) {
    final next = _paymentTail.then((_) => action());
    _paymentTail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  Future<PaymentIntent?> pendingPaymentIntent(String invoice) async {
    final owner = _owner();
    if (owner == null) throw StateError('Sign in to restore this payment');
    final result = await _intents.read(owner, invoice);
    if (_owner() != owner) throw StateError('Payment account changed');
    return result;
  }

  Future<void> finishPaymentIntent(String invoice, String paymentId) =>
      _serializePayment(() async {
        final owner = _owner();
        if (owner == null) return;
        final intent = await _intents.read(owner, invoice);
        if (intent?.paymentId == paymentId) {
          await _intents.remove(owner, invoice);
        }
      });

  Future<({String? paymentId, String? error})> recordPayment({
    required String invoiceId,
    required Money amount,
    required PaymentSource source,
    String? reference,
  }) => _serializePayment(() async {
    final owner = _owner();
    if (owner == null) {
      return (paymentId: null, error: 'Sign in before recording a payment.');
    }
    PaymentIntent intent;
    bool existing;
    try {
      final saved = await _intents.read(owner, invoiceId);
      existing = saved != null;
      intent =
          saved ??
          PaymentIntent(
            key: newIdempotencyKey(),
            invoiceId: invoiceId,
            amount: amount.toBackendString(),
            source: source.wire,
            reference: reference == null || reference.isEmpty
                ? null
                : reference,
          );
      if (intent.amount != amount.toBackendString() ||
          intent.source != source.wire ||
          intent.reference !=
              (reference == null || reference.isEmpty ? null : reference)) {
        return (
          paymentId: null,
          error:
              'An earlier payment needs reconciliation. Retry its original details before starting another payment.',
        );
      }
      if (saved == null) await _intents.write(owner, intent);
      if (_owner() != owner) {
        return (
          paymentId: null,
          error:
              'Payment account changed. Return to the original account to retry.',
        );
      }
      if (intent.paymentId != null) {
        return (paymentId: intent.paymentId, error: null);
      }
    } catch (_) {
      return (
        paymentId: null,
        error:
            'Payment recovery storage is unavailable. No payment request was sent.',
      );
    }
    try {
      final res = await dio.post<dynamic>(
        '/api/fee/payments',
        data: intent.body,
        options: Options(
          responseType: ResponseType.plain,
          extra: {if (_pinOwner) 'expectedOwner': owner},
        ),
      );
      final body =
          jsonDecode(FinanceJson.quoteMoney(res.data as String))
              as Map<String, dynamic>;
      final id = body['id'] as String?;
      if (id == null || id.isEmpty) {
        throw const FormatException('Missing payment receipt');
      }
      await _intents.write(owner, intent.recorded(id));
      if (_owner() != owner) {
        return (
          paymentId: null,
          error: 'Payment result saved for the original account.',
        );
      }
      return (paymentId: id, error: null);
    } on DioException catch (err) {
      final code = err.response?.statusCode;
      if (!existing && const [400, 403, 404, 422].contains(code)) {
        try {
          await _intents.remove(owner, invoiceId);
        } catch (_) {}
        return (paymentId: null, error: _message(err));
      }
      return (
        paymentId: null,
        error:
            'Payment outcome is not confirmed. Retry the original payment; do not enter it as a new payment. ${_message(err)}',
      );
    } catch (_) {
      return (
        paymentId: null,
        error:
            'Payment outcome is not confirmed. Its original reference is saved; retry to reconcile it.',
      );
    }
  });

  Future<List<Map<String, dynamic>>> loadDiscountRequests(String invoiceId) =>
      _array('/api/fee/invoices/$invoiceId/discount-requests');

  Future<String> requestDiscount({
    required String invoiceId,
    required String value,
    required bool percentage,
    required String description,
  }) => _serializePayment(() async {
    final owner = _owner();
    if (owner == null) {
      throw StateError('Sign in before requesting a discount.');
    }
    final scope = 'discount:$invoiceId';
    final saved = await _intents.read(owner, scope);
    final intent =
        saved ??
        PaymentIntent(
          key: newIdempotencyKey(),
          invoiceId: scope,
          amount: value,
          source: percentage ? 'DISCOUNT_PERCENTAGE' : 'DISCOUNT_AMOUNT',
          reference: description,
        );
    if (intent.amount != value ||
        intent.source !=
            (percentage ? 'DISCOUNT_PERCENTAGE' : 'DISCOUNT_AMOUNT') ||
        intent.reference != description) {
      throw StateError(
        'Reconcile the earlier discount using its original details.',
      );
    }
    if (saved == null) await _intents.write(owner, intent);
    if (_owner() != owner) {
      throw StateError(
        'Account changed. Return to the original account to reconcile.',
      );
    }
    if (intent.paymentId != null) return intent.paymentId!;
    try {
      final response = await dio.post<dynamic>(
        '/api/fee/invoices/$invoiceId/discount',
        data: {
          'type': 'custom',
          'description': description,
          percentage ? 'percentage' : 'amount': value,
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Idempotency-Key': intent.key},
          extra: {if (_pinOwner) 'expectedOwner': owner},
        ),
      );
      final raw = jsonDecode(FinanceJson.quoteMoney(response.data as String));
      final id = (raw as Map)['id'] as String;
      await _intents.write(owner, intent.recorded(id));
      if (_owner() != owner) {
        throw StateError('Result saved for the original account.');
      }
      return id;
    } on DioException catch (error) {
      if (saved == null &&
          const [400, 403, 404, 422].contains(error.response?.statusCode)) {
        await _intents.remove(owner, scope);
      }
      throw mapDioError(_decodeErrorBody(error));
    } on Object {
      // Preserve the frozen identity for uncertain results, including storage failures.
      rethrow;
    }
  });

  Future<void> decideDiscount(
    String id, {
    required bool approve,
    String? reason,
  }) async {
    await _json(
      () => dio.post<dynamic>(
        '/api/fee/discount-requests/$id/${approve ? 'approve' : 'reject'}',
        data: reason == null ? <String, Object?>{} : {'reason': reason},
        options: _plain,
      ),
    );
  }

  Future<List<PendingPayment>> loadPending() async {
    final rows = await _array('/api/fee/payments/pending');
    return rows.map(PendingPayment.fromJson).toList();
  }

  /// Approves a payment and returns its receipt reference.
  ///
  /// 🔴 There is no way back from here: no void, no reverse, no delete, and
  /// the payment cannot even be READ by id afterwards. The screen states
  /// that before the button is pressed.
  ///
  /// [alreadyProcessed] is true only for the server's specific "this payment
  /// is no longer pending" answers (see [isAlreadyProcessed]) — never for an
  /// overpayment conflict or any other refusal. The caller must not retry.
  Future<({ApprovalResult? result, String? error, bool alreadyProcessed})>
  approvePayment(String paymentId) async {
    try {
      final res = await dio.post<dynamic>(
        '/api/fee/payments/$paymentId/approve',
        data: const <String, dynamic>{},
        options: _plain,
      );
      final body =
          jsonDecode(FinanceJson.quoteMoney(res.data as String))
              as Map<String, dynamic>;
      return (
        result: ApprovalResult.fromJson(body),
        error: null,
        alreadyProcessed: false,
      );
    } on DioException catch (err) {
      final message = _message(err);
      return (
        result: null,
        error: message,
        alreadyProcessed: isAlreadyProcessed(err.response?.statusCode, message),
      );
    }
  }

  /// The server's two answers for a payment that is no longer pending
  /// (FeeService.approvePayment / rejectPayment):
  ///  - 400 "Payment is already STATUS" — the pre-check (e.g. a repeat after
  ///    a lost response, or someone else decided first);
  ///  - 409 "Payment was already processed" — the atomic claim lost a race.
  /// Other 409s ("Payment exceeds the current outstanding balance") and every
  /// other refusal are NOT this, and stay ordinary errors.
  static bool isAlreadyProcessed(int? status, String message) =>
      (status == 409 && message == 'Payment was already processed') ||
      (status == 400 && message.startsWith('Payment is already '));

  /// The status the server named in "Payment is already STATUS", if any.
  static String? processedStatus(String message) {
    const prefix = 'Payment is already ';
    return message.startsWith(prefix)
        ? message.substring(prefix.length).trim()
        : null;
  }

  /// Rejects a payment. Only possible BEFORE approval — afterwards the
  /// backend answers "Payment is already approved".
  /// Rejects with a reason, on the existing API field (`RejectBody.reason`,
  /// stored as `payment.rejection_reason` by FeeService). Whether guardians
  /// are shown the reason is the server's decision; this does not assume it.
  Future<({String? error, bool alreadyProcessed})> rejectPaymentWithReason(
    String paymentId,
    String reason,
  ) async {
    try {
      await dio.post<dynamic>(
        '/api/fee/payments/$paymentId/reject',
        data: <String, dynamic>{'reason': reason.trim()},
        options: _plain,
      );
      return (error: null, alreadyProcessed: false);
    } on DioException catch (err) {
      final message = _message(err);
      return (
        error: message,
        alreadyProcessed: isAlreadyProcessed(err.response?.statusCode, message),
      );
    }
  }

  Future<String?> rejectPayment(String paymentId) async {
    try {
      await dio.post<dynamic>(
        '/api/fee/payments/$paymentId/reject',
        data: const <String, dynamic>{},
        options: _plain,
      );
      return null;
    } on DioException catch (err) {
      return _message(err);
    }
  }

  Future<Receipt> loadReceipt(String receiptId) async =>
      Receipt.fromJson(await _object('/api/fee/receipts/$receiptId'));

  // --- Reports ---------------------------------------------------------------

  /// No parameters are sent: this endpoint accepts `period` and
  /// `academicYearId` and IGNORES both — `period=1999-01` returned identical
  /// figures. Sending them would imply a scope the numbers do not have.
  Future<CollectionReport> loadCollectionReport() async =>
      CollectionReport.fromJson(await _object('/api/fee/reports/collection'));

  /// Unlike the collection report, this one DOES honour its filters — both
  /// controlled with a bogus id and a bogus period.
  Future<List<DefaulterRow>> loadDefaulters({
    String? classId,
    String? period,
  }) async {
    final rows = await _array('/api/fee/reports/defaulters', {
      'classId': ?classId,
      'period': ?period,
    });
    return rows.map(DefaulterRow.fromJson).toList();
  }

  // --- Errors ----------------------------------------------------------------

  /// The backend's message where there is one.
  ///
  /// 🔴 Status is NOT used to classify: this surface answers **409 for plain
  /// validation failures** ("Conflicts with existing data" for a fee head
  /// with no name), exactly like the timetable did. Rendering "that already
  /// exists" over a missing field would send an admin hunting for a
  /// duplicate that is not there.
  static String _message(DioException err) {
    final body = err.response?.data;
    String? message;
    if (body is Map) {
      message = body['message'] as String?;
    } else if (body is String && body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) message = decoded['message'] as String?;
      } on FormatException {
        message = null;
      }
    }
    if (message != null && message.isNotEmpty) return message;
    final failure = mapDioError(err);
    return failure.message ?? 'This could not be saved.';
  }

  /// Re-decodes a plain-text error body into a Map before it is mapped.
  ///
  /// 🔴 Necessary because this repository asks dio for `ResponseType.plain`
  /// — that is what keeps money away from `jsonDecode`'s number parser.
  /// `mapDioError` reads `message` only when the body is already a Map, so
  /// without this every server message on a read path was silently replaced
  /// by a generic fallback.
  static DioException _decodeErrorBody(DioException err) {
    final response = err.response;
    final body = response?.data;
    if (body is! String || body.isEmpty) return err;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return err;
      return err.copyWith(
        response: Response<dynamic>(
          data: decoded,
          statusCode: response!.statusCode,
          statusMessage: response.statusMessage,
          headers: response.headers,
          requestOptions: response.requestOptions,
        ),
      );
    } on FormatException {
      return err;
    }
  }

  static String _uuidV4() {
    final random = _random;
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int from, int to) => bytes
        .sublist(from, to)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}

final _random = Random();
