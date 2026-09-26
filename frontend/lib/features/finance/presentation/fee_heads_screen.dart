import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/states/screen_state.dart';
import '../../../core/widgets/states/screen_state_builder.dart';
import '../../setup/presentation/academic_years_screen.dart' show setupListHeight;
import '../../setup/presentation/setup_scaffold.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import '../domain/money.dart';

/// Screen 1: fee heads — the named components of a fee.
///
/// Create-only, like most of this backend: there is no `PUT` and no
/// `DELETE` on `/api/fee/heads` (both 404), so no row offers an edit or a
/// remove it cannot honour (D-19). The form says so before saving, not
/// after.
class FeeHeadsScreen extends StatefulWidget {
  const FeeHeadsScreen({required this.repository, super.key});

  final FinanceRepository repository;

  @override
  State<FeeHeadsScreen> createState() => FeeHeadsScreenState();
}

class FeeHeadsScreenState extends State<FeeHeadsScreen> {
  ScreenState<List<FeeHead>> _state =
      const ScreenState<List<FeeHead>>.loading();

  String _name = '';
  String _taxRate = '';
  bool _recurring = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() =>
        _state = ScreenState<List<FeeHead>>.loading(previous: _state.data));
    try {
      final heads = await widget.repository.loadHeads();
      if (!mounted) return;
      setState(() => _state = ScreenState<List<FeeHead>>.data(heads));
    } on Object catch (e) {
      if (!mounted) return;
      final f = e is LoadFailure ? e : const LoadFailure();
      setState(() => _state = ScreenState<List<FeeHead>>.failed(
            f,
            cached: _state.data,
            connection:
                f.unreachable ? NetworkStatus.offline : NetworkStatus.online,
          ));
    }
  }

  Future<String?> _create() async {
    final rate = _taxRate.trim();
    // A rate is not an amount, but it is the same shape — a decimal with at
    // most two places — so the same exact scanner validates it. Nothing is
    // stored as Money here; the rate is sent on as text.
    if (rate.isNotEmpty && Money.tryParse(rate) == null) {
      return 'A tax rate is a number with up to two decimals, such as 5 or '
          '5.50.';
    }
    try {
      await widget.repository.createHead(
        name: _name.trim(),
        isRecurring: _recurring,
        taxRate: rate.isEmpty ? '0' : rate,
      );
      if (!mounted) return null;
      setState(() {
        _name = '';
        _taxRate = '';
        _recurring = true;
      });
      await _load();
      return null;
    } on LoadFailure catch (f) {
      return f.message ?? 'The fee head could not be created.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SetupScaffold(
      title: 'Fee heads',
      children: [
        CreatePanel(
          addLabel: 'Add a fee head',
          canSubmit: _name.trim().isNotEmpty,
          onSubmit: _create,
          confirmNote: 'A fee head cannot be renamed or removed afterwards — '
              'this backend has no edit or delete for them.',
          fields: [
            SetupField(
              label: 'Name',
              value: _name,
              placeholder: 'e.g. Tuition Fee',
              onChanged: (v) => setState(() => _name = v),
            ),
            SetupField(
              label: 'Tax rate % (optional)',
              value: _taxRate,
              placeholder: 'e.g. 5.50',
              onChanged: (v) => setState(() => _taxRate = v),
            ),
            // A plain Row rather than a SwitchListTile: a ListTile paints on
            // the nearest Material, and the create panel is a decorated
            // container, so its background would hide the tile's own.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Charged every period',
                        style: AppTypography.personName
                            .copyWith(color: context.tokens.textPrimary),
                      ),
                      Text(
                        'Off for a one-off charge such as admission.',
                        style: AppTypography.bodyAdminMeta
                            .copyWith(color: context.tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _recurring,
                  onChanged: (v) => setState(() => _recurring = v),
                ),
              ],
            ),
          ],
        ),
        SizedBox(
          height: setupListHeight(context),
          child: ScreenStateBuilder<List<FeeHead>>(
            state: _state,
            onRetry: _load,
            emptyTitle: 'No fee heads yet',
            emptyMessage:
                'A fee head is one named part of a fee — tuition, transport, '
                'admission. Fee plans are assembled from these.',
            emptyIcon: Icons.receipt_long_outlined,
            data: (context, heads) => ListView(
              children: [
                for (final h in heads)
                  SetupRow(
                    title: h.name,
                    detail: h.isRecurring ? 'Every period' : 'One-off',
                    trailing: h.hasTax ? 'Tax ${h.taxRate}%' : null,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
