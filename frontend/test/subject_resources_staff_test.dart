import 'dart:async';
import 'dart:convert';

import 'dart:ui' show Tristate;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academics/data/subject_resources_repository.dart';
import 'package:smartems/features/academics/presentation/subject_resources_screen.dart';
import 'package:smartems/features/setup/domain/setup_models.dart';

/// D-21 staff screen against a deterministic stub of the resource endpoints.
/// This is component behaviour only, not live backend verification.
class _ResourceServer implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int listStatus = 200;
  List<Map<String, dynamic>> resources = [];
  int deleteStatus = 204;

  /// When set, the upload waits on it (to observe the busy state).
  Completer<void>? holdUpload;

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    if (s != null) await s.drain<void>();
    final path = o.uri.path;
    if (o.method == 'GET' && path == '/api/subjects/sub-1/resources') {
      if (listStatus != 200) {
        return _json(listStatus, {'message': 'You may not manage this.'});
      }
      return _json(200, resources);
    }
    if (o.method == 'POST' && path == '/api/subjects/sub-1/resources') {
      return _json(201, {'id': _newId});
    }
    if (o.method == 'POST' && path == '/api/files') {
      await holdUpload?.future;
      return _json(201, {'id': _fileId});
    }
    if (o.method == 'POST' && path == '/api/subject-resources/$_newId/file') {
      return _json(200, {'id': _newId, 'status': 'active'});
    }
    if (o.method == 'GET' && path == '/api/files/$_fileId/content') {
      return ResponseBody.fromBytes(utf8.encode('%PDF-1.4 test'), 200,
          headers: {
            Headers.contentTypeHeader: ['application/pdf'],
          });
    }
    if (o.method == 'DELETE' && path.startsWith('/api/subject-resources/')) {
      return deleteStatus == 204
          ? ResponseBody.fromString('', 204)
          : _json(deleteStatus, {'message': 'Not allowed.'});
    }
    return _json(404, {'message': 'Not found'});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

const _fileId = '0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b';
const _newId = '0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a60';

final class _MemoryFile extends PlatformFile {
  _MemoryFile(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.parse('memory:///$name');
  @override
  get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _FakePicker extends FilePickerPlatform {
  PlatformFile? next;
  List<String>? lastAllowed;
  final List<String> saved = [];

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    lastAllowed = allowedExtensions;
    return next;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saved.add('$fileName:$mimeType:${utf8.decode(bytes)}');
    return Uri.parse('file:///saved/$fileName');
  }
}

const _year = AcademicYear(
  id: 'year-1',
  name: '2026',
  startDate: '2026-01-01',
  endDate: '2026-12-31',
  current: true,
);
const _class = SchoolClass(id: 'class-1', name: 'Class 8', levelOrder: 8);
const _subject = Subject(id: 'sub-1', name: 'Mathematics');

Map<String, dynamic> _fileRow({bool canDelete = true}) => {
      'id': 'res-1',
      'title': 'Algebra notes',
      'kind': 'file',
      'status': 'active',
      'filename': 'algebra.pdf',
      'contentType': 'application/pdf',
      'sizeBytes': 2048,
      'contentPath': '/api/files/$_fileId/content',
      'canDelete': canDelete,
    };

final _linkRow = {
  'id': 'res-2',
  'title': 'Reading list',
  'kind': 'link',
  'status': 'active',
  'url': 'https://example.org/reading',
  'canDelete': false,
};

late _FakePicker _picker;

({_ResourceServer server, Widget app}) _wire() {
  final server = _ResourceServer();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server;
  return (
    server: server,
    app: MaterialApp(
      theme: AppTheme.light(role: AppRole.teacher),
      home: SubjectResourcesScreen(
        repository: SubjectResourcesRepository(dio),
        year: _year,
        classes: const [_class],
        subjects: const [_subject],
      ),
    ),
  );
}

Future<void> _openFileSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('resource-add-file')));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String name, int size) async {
  _picker.next = _MemoryFile(name, Uint8List(size));
  await tester.tap(find.byKey(const Key('resource-pick')));
  await tester.pumpAndSettle();
}

/// Is the sheet's Add button enabled?
({bool enabled}) _submit(WidgetTester tester) {
  final semantics =
      tester.getSemantics(find.byKey(const Key('resource-submit')));
  return (enabled: semantics.flagsCollection.isEnabled == Tristate.isTrue);
}

void main() {
  setUp(() {
    _picker = _FakePicker();
    FilePickerPlatform.instance = _picker;
  });

  testWidgets('lists resources for the scoped subject/class/year; delete only '
      'where the server allows', (tester) async {
    final w = _wire()..server.resources = [_fileRow(), _linkRow];
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();

    final list = w.server.requests.firstWhere((r) => r.method == 'GET');
    expect(list.uri.path, '/api/subjects/sub-1/resources');
    expect(list.uri.queryParameters,
        {'classId': 'class-1', 'academicYearId': 'year-1'});
    expect(find.text('Algebra notes'), findsOneWidget);
    expect(find.text('Reading list'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    // canDelete only on the file row.
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('an assigned teacher without delete rights sees no Remove',
      (tester) async {
    final w = _wire()..server.resources = [_fileRow(canDelete: false)];
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    expect(find.text('Algebra notes'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('permission denied (403) shows the access-denied state, no '
      'resources', (tester) async {
    final w = _wire()..server.listStatus = 403;
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNothing);
    expect(find.text('No resources yet'), findsNothing);
    expect(find.text('You don’t have access to this'), findsOneWidget);
    expect(find.text('You may not manage this.'), findsOneWidget);
  });

  testWidgets('a server failure (500) shows an error with retry',
      (tester) async {
    final w = _wire()..server.listStatus = 500;
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNothing);
    w.server
      ..listStatus = 200
      ..resources = [_fileRow()];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Algebra notes'), findsOneWidget);
  });

  testWidgets('file picker uses the approved allowlist; a disallowed type is '
      'refused', (tester) async {
    final w = _wire();
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await _openFileSheet(tester);
    await _pick(tester, 'virus.exe', 10);

    expect(_picker.lastAllowed,
        ['pdf', 'png', 'jpg', 'jpeg', 'docx', 'xlsx', 'pptx', 'txt']);
    expect(find.textContaining('Use a PDF, image'), findsOneWidget);
    expect(_submit(tester).enabled, isFalse);
    expect(w.server.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('an oversized file (> 8 MB) is refused before any upload',
      (tester) async {
    final w = _wire();
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await _openFileSheet(tester);
    await _pick(tester, 'big.pdf', 8 * 1024 * 1024 + 1);

    expect(find.text('The file must be smaller than 8 MB.'), findsOneWidget);
    expect(_submit(tester).enabled, isFalse);
    expect(w.server.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    final w = _wire();
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await _openFileSheet(tester);
    _picker.next = null;
    await tester.tap(find.byKey(const Key('resource-pick')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Up to 8 MB'), findsOneWidget);
    expect(_submit(tester).enabled, isFalse);
    expect(w.server.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('a valid file: busy state, create + upload + attach with stable '
      'idempotency key, then success', (tester) async {
    final w = _wire()..server.holdUpload = Completer<void>();
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await _openFileSheet(tester);
    await _pick(tester, 'chapter3.pdf', 1024);
    expect(_submit(tester).enabled, isTrue);

    await tester.tap(find.byKey(const Key('resource-submit')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Adding…'), findsOneWidget);

    w.server.holdUpload!.complete();
    await tester.pumpAndSettle();

    final posts = w.server.requests.where((r) => r.method == 'POST').toList();
    expect(posts.map((r) => r.uri.path), [
      '/api/subjects/sub-1/resources',
      '/api/files',
      '/api/subject-resources/$_newId/file',
    ]);
    final create = posts.first;
    expect(create.headers['Idempotency-Key'], isA<String>());
    expect((create.data as Map)['kind'], 'file');
    expect((create.data as Map)['title'], 'chapter3');
    expect(posts.last.data, {'fileId': _fileId});
    expect(find.text('File added.'), findsOneWidget);
  });

  testWidgets('a link must be https before it can be added', (tester) async {
    final w = _wire();
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resource-add-link')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.descendant(
            of: find.byKey(const Key('resource-title')),
            matching: find.byType(EditableText)),
        'Reading');
    await tester.enterText(
        find.descendant(
            of: find.byKey(const Key('resource-url')),
            matching: find.byType(EditableText)),
        'http://example.org');
    await tester.pump();
    expect(_submit(tester).enabled, isFalse);

    await tester.enterText(
        find.descendant(
            of: find.byKey(const Key('resource-url')),
            matching: find.byType(EditableText)),
        'https://example.org');
    await tester.pump();
    expect(_submit(tester).enabled, isTrue);
    await tester.tap(find.byKey(const Key('resource-submit')));
    await tester.pumpAndSettle();

    final create = w.server.requests.firstWhere((r) => r.method == 'POST');
    expect((create.data as Map)['kind'], 'link');
    expect((create.data as Map)['url'], 'https://example.org');
    expect(find.text('Link added.'), findsOneWidget);
  });

  testWidgets('Download fetches authenticated bytes and saves them',
      (tester) async {
    final w = _wire()..server.resources = [_fileRow()];
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(
        w.server.requests.any((r) =>
            r.method == 'GET' && r.uri.path == '/api/files/$_fileId/content'),
        isTrue);
    expect(_picker.saved, ['algebra.pdf:application/pdf:%PDF-1.4 test']);
  });

  testWidgets('Remove asks first; Cancel deletes nothing', (tester) async {
    final w = _wire()..server.resources = [_fileRow()];
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this resource?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(w.server.requests.where((r) => r.method == 'DELETE'), isEmpty);
    expect(find.text('Algebra notes'), findsOneWidget);
  });

  testWidgets('Remove confirmed deletes and reloads', (tester) async {
    final w = _wire()..server.resources = [_fileRow()];
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    w.server.resources = [];
    await tester.tap(find.descendant(
        of: find.byType(Dialog), matching: find.text('Remove')).last);
    await tester.pumpAndSettle();

    final del = w.server.requests.where((r) => r.method == 'DELETE').single;
    expect(del.uri.path, '/api/subject-resources/res-1');
    expect(find.text('Resource removed.'), findsOneWidget);
    expect(find.text('No resources yet'), findsOneWidget);
  });

  testWidgets('a backend refusal on delete is shown and the row stays',
      (tester) async {
    final w = _wire()
      ..server.resources = [_fileRow()]
      ..server.deleteStatus = 403;
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(Dialog), matching: find.text('Remove')).last);
    await tester.pumpAndSettle();
    expect(find.text('Resource removed.'), findsNothing);
    expect(find.text('Algebra notes'), findsOneWidget);
  });

  testWidgets('keyboard: Add a file is reachable with Tab and opens with Enter',
      (tester) async {
    final w = _wire();
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused != null &&
          find
              .ancestor(
                  of: find.byWidget(focused.widget),
                  matching: find.byKey(const Key('resource-add-file')))
              .evaluate()
              .isNotEmpty) {
        break;
      }
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('resource-pick')), findsOneWidget);
  });

  testWidgets('phone width (360 dp) with 1.3x text renders without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final w = _wire()..server.resources = [_fileRow(), _linkRow];
    await tester.pumpWidget(w.app);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Algebra notes'), findsOneWidget);
  });
}
