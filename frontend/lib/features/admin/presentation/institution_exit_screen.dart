import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class InstitutionExitScreen extends StatefulWidget {
  const InstitutionExitScreen({required this.dio, super.key});
  final Dio dio;
  @override
  State<InstitutionExitScreen> createState() => _InstitutionExitScreenState();
}

class _InstitutionExitScreenState extends State<InstitutionExitScreen> {
  Map<String, dynamic>? data;
  String reason = '';
  String? error;
  bool busy = false, confirmed = false;
  final operation = const Uuid().v4();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.dio.get<Map<String, dynamic>>(
        '/api/institution-exit',
      );
      if (mounted) setState(() => data = r.data);
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Institution owner access required or service unavailable.',
        );
      }
    }
  }

  Future<void> _start() async {
    setState(() => busy = true);
    try {
      await widget.dio.post<dynamic>(
        '/api/institution-exit',
        data: {'operationId': operation, 'reason': reason.trim()},
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = 'Exit was not confirmed. Refresh status before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => busy = true);
    try {
      final r = await widget.dio.get<List<int>>(
        '/api/institution-exit/export',
        options: Options(responseType: ResponseType.bytes),
      );
      await FilePicker.saveFile(
        dialogTitle: 'Save partial domain data snapshot',
        fileName: 'institution-domain-export.zip',
        bytes: Uint8List.fromList(r.data!),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Export could not be saved. This is not a complete exit backup.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Institution exit')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Owner-only exit makes the institution read-only. Production permanent deletion is disabled pending legal retention and approval decisions.',
        ),
        if (error != null) Text(error!),
        if (data == null)
          TextButton(
            onPressed: busy ? null : _load,
            child: const Text('Refresh status'),
          ),
        if (data != null) ...[
          Text('State: ${data!['state']}'),
          Text('Active legal holds: ${data!['activeHolds']}'),
          const Text(
            'The 30-day export and later 90-day planning markers are provisional. Elapsed time does not authorize deletion.',
          ),
          for (final b in (data!['blockers'] as List? ?? []))
            Text(b.toString()),
          if (data!['state'] == 'active') ...[
            TextField(
              decoration: const InputDecoration(labelText: 'Exit reason'),
              onChanged: (v) => setState(() => reason = v),
            ),
            CheckboxListTile(
              title: const Text(
                'I understand ordinary changes will stop; this does not authorize deletion.',
              ),
              value: confirmed,
              onChanged: busy
                  ? null
                  : (v) => setState(() => confirmed = v ?? false),
            ),
            TextButton(
              onPressed: !busy && confirmed && reason.trim().isNotEmpty
                  ? _start
                  : null,
              child: const Text('Request read-only exit'),
            ),
          ],
          if (data!['state'] == 'export_only') ...[
            const Text(
              'Partial database snapshot only: authentication secrets, managed-file bytes and unsupported tables are excluded. The ZIP manifest lists coverage and hashes. This cannot establish completed exit export.',
            ),
            TextButton(
              onPressed: busy ? null : _export,
              child: const Text('Download partial data snapshot'),
            ),
          ],
          TextButton(
            onPressed: busy ? null : _load,
            child: const Text('Refresh'),
          ),
        ],
      ],
    ),
  );
}
