import 'package:flutter/material.dart';
import '../data/academics_repository.dart';
import '../domain/academic_models.dart';

class CurriculumReviewScreen extends StatefulWidget {
  const CurriculumReviewScreen({
    required this.repository,
    required this.chapter,
    super.key,
  });
  final AcademicsRepository repository;
  final Chapter chapter;
  @override
  State<CurriculumReviewScreen> createState() => _CurriculumReviewScreenState();
}

class _CurriculumReviewScreenState extends State<CurriculumReviewScreen> {
  List<Map<String, dynamic>>? versions;
  final selected = <String>{};
  String reason = '', name = '';
  String? error;
  bool busy = false, adopt = false, finished = false;
  @override
  void initState() {
    super.initState();
    name = widget.chapter.name;
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.repository.curriculumVersions(
        widget.chapter.id,
      );
      if (mounted) {
        setState(() {
          versions = rows;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) setState(() => finished = true);
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.chapter;
    final enabled = !busy && !finished && versions != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Curriculum review')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(c.name),
          Text(
            c.adopted
                ? 'Adopted official curriculum'
                : 'Draft or legacy content; explicit review is required for official use.',
          ),
          if (error != null) Text(error!, key: const Key('curriculum-error')),
          if (versions == null)
            TextButton(
              onPressed: busy ? null : _load,
              child: const Text('Load versions'),
            ),
          if (finished)
            const Text(
              'Saved. Return to the syllabus to refresh available actions.',
            ),
          if (c.canEdit) ...[
            TextFormField(
              initialValue: name,
              decoration: const InputDecoration(
                labelText: 'Draft chapter name',
              ),
              onChanged: (v) => name = v,
            ),
            TextButton(
              onPressed: enabled && name.trim().isNotEmpty
                  ? () => _run(
                      () => widget.repository.renameCurriculumDraft(
                        c.id,
                        name.trim(),
                      ),
                    )
                  : null,
              child: const Text('Save draft name'),
            ),
          ],
          if (c.status == 'active')
            TextButton(
              onPressed: enabled
                  ? () => _run(
                      () => widget.repository.curriculumAction(
                        'chapters/${c.id}/draft-revision',
                      ),
                    )
                  : null,
              child: const Text('Create draft revision'),
            ),
          if (c.canPublish) ...[
            const Text(
              'Select exactly the reviewed topics; no topics are selected automatically.',
            ),
            for (final t in c.topics)
              CheckboxListTile(
                title: Text(t.name),
                value: selected.contains(t.id),
                onChanged: enabled
                    ? (v) => setState(() {
                        if (v == true) {
                          selected.add(t.id);
                        } else {
                          selected.remove(t.id);
                        }
                      })
                    : null,
              ),
            TextField(
              decoration: const InputDecoration(labelText: 'Review reason'),
              onChanged: (v) => setState(() => reason = v),
            ),
            SwitchListTile(
              title: const Text('Adopt this version for official reports'),
              value: adopt,
              onChanged: enabled ? (v) => setState(() => adopt = v) : null,
            ),
            TextButton(
              onPressed: enabled && reason.trim().isNotEmpty
                  ? () => _run(
                      () => widget.repository
                          .curriculumAction('chapters/${c.id}/publish', {
                            'expectedPreviousVersion': versions!.isEmpty
                                ? null
                                : versions!.first['id'],
                            'topicIds': selected.toList(),
                            'adopt': adopt,
                            'reason': reason.trim(),
                          }),
                    )
                  : null,
              child: const Text('Publish reviewed version'),
            ),
            if (c.status == 'proposed')
              TextButton(
                onPressed: enabled && reason.trim().isNotEmpty
                    ? () => _run(
                        () => widget.repository.curriculumAction(
                          'chapters/${c.id}/reject',
                          {'reason': reason.trim()},
                        ),
                      )
                    : null,
                child: const Text('Reject draft'),
              ),
          ],
          for (final v in versions ?? <Map<String, dynamic>>[])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Version ${v['version']} - ${v['adopted'] == true ? 'Adopted' : 'Published'}',
                    ),
                    Text('Approver: ${v['approver_id']}'),
                    Text('Published: ${v['published_at']}'),
                    Text('Reason: ${v['reason']}'),
                    Text('Hash: ${v['content_hash']}'),
                    Text('${v['content']}'),
                    if (c.canPublish && v['adopted'] != true)
                      TextButton(
                        onPressed: enabled
                            ? () => _run(
                                () => widget.repository.curriculumAction(
                                  'publications/${v['id']}/adopt',
                                ),
                              )
                            : null,
                        child: const Text('Adopt version'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
