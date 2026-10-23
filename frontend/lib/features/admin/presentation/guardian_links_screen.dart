import 'package:flutter/material.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../setup/presentation/setup_scaffold.dart';
import '../data/admin_repository.dart';

class GuardianLinksScreen extends StatefulWidget {
  const GuardianLinksScreen({
    required this.repository,
    required this.studentId,
    super.key,
  });
  final AdminRepository repository;
  final String studentId;
  @override
  State<GuardianLinksScreen> createState() => _GuardianLinksScreenState();
}

class _GuardianLinksScreenState extends State<GuardianLinksScreen> {
  List<Map<String, dynamic>>? _links;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _links = null;
      _error = null;
    });
    try {
      final links = await widget.repository.loadGuardianLinks(widget.studentId);
      if (mounted) {
        setState(() => _links = links);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = e is LoadFailure
              ? e.message ?? 'Guardian review unavailable.'
              : 'Guardian review unavailable.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _review(Map<String, dynamic> link) async {
    String reason = '';
    String status = 'active';
    final grants = <String, bool>{
      for (final category in [
        'academic',
        'attendance',
        'finance',
        'documents',
        'communication',
      ])
        category: false,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Review guardian relationship'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Verify the relationship independently. Emergency contact status alone grants no browsing. Do not enter sensitive custody details here.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Decision'),
                    items: [
                      const DropdownMenuItem(
                        value: 'active',
                        child: Text('Verify with explicit categories'),
                      ),
                      const DropdownMenuItem(
                        value: 'suspended',
                        child: Text('Suspend'),
                      ),
                      const DropdownMenuItem(
                        value: 'revoked',
                        child: Text('Revoke'),
                      ),
                      if (link['link_status'] == 'unreviewed')
                        const DropdownMenuItem(
                          value: 'rejected',
                          child: Text('Reject verification'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        update(() => status = value);
                      }
                    },
                  ),
                  if (status == 'active') ...[
                    for (final category in grants.keys)
                      SwitchListTile(
                        title: Text(
                          category == 'communication'
                              ? 'Receive communications'
                              : 'View $category',
                        ),
                        value: grants[category]!,
                        onChanged: (value) =>
                            update(() => grants[category] = value),
                      ),
                    const Text(
                      'Leave every browsing category off for a contact-only relationship.',
                    ),
                  ],
                  TextField(
                    onChanged: (value) => reason = value,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: status == 'active'
                          ? 'Verification evidence reference'
                          : 'Decision reason',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Record review'),
            ),
          ],
        ),
      ),
    );
    final evidence = reason.trim();
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.reviewGuardianLink(
        link['id'] as String,
        status: status,
        reason: evidence,
        categories: status == 'active' ? grants : null,
      );
      if (mounted) {
        await _load();
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _links = null;
          _error = e is LoadFailure
              ? e.message ?? 'Review not confirmed. Refresh before retrying.'
              : 'Review not confirmed. Refresh before retrying.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SetupScaffold(
    title: 'Guardian access',
    children: [
      const Text(
        'Pending relationships have no child-data access. Each verified child relationship has separate categories. Revocation takes effect for new reads and deliveries.',
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!),
      TextButton(
        onPressed: _busy ? null : _load,
        child: const Text('Refresh relationships'),
      ),
      if (_links != null && _links!.isEmpty)
        const Text('No guardian relationships recorded.'),
      for (final link in _links ?? <Map<String, dynamic>>[])
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${link['first_name']} ${link['last_name']} - ${link['link_status']}',
                ),
                if (link['is_emergency_contact'] == true)
                  const Text('Emergency contact'),
                Text('Verified: ${link['verified_at'] ?? 'Not verified'}'),
                Text(
                  'Allowed categories: ${[
                    for (final c in ['academic', 'attendance', 'finance', 'documents'])
                      if (link['can_view_$c'] == true && link['link_status'] == 'active') c,
                  ].join(', ')}',
                ),
                if (link['link_status'] == 'active' &&
                    ![
                      'academic',
                      'attendance',
                      'finance',
                      'documents',
                    ].any((c) => link['can_view_$c'] == true))
                  const Text('Contact only - no protected browsing'),
                if (!['revoked', 'rejected'].contains(link['link_status']))
                  TextButton(
                    onPressed: _busy ? null : () => _review(link),
                    child: const Text('Review relationship'),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
}
