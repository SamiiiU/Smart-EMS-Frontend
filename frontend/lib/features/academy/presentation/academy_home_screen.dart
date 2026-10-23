import 'package:flutter/material.dart';

import '../../../core/widgets/page_header.dart';
import '../data/academy_repository.dart';
import 'academy_common.dart';
import 'batches_screen.dart';
import 'courses_screen.dart';
import 'offerings_screen.dart';

/// Staff Academy workspace. Academy managers (`academy.manage` on at least
/// one campus) get Batches · Courses · Offerings; instructors without it get
/// only the batches they currently teach. Shown only when the institution
/// profile is ACADEMY (the router decides that).
class AcademyHomeScreen extends StatefulWidget {
  const AcademyHomeScreen({
    required this.repository,
    this.feesAvailable = false,
    super.key,
  });

  final AcademyRepository repository;

  /// True when this account holds fee.manage somewhere (batch fee panel).
  final bool feesAvailable;

  /// DEF-08: the selected manager tab survives the shell switching between desktop and phone
  /// layouts (resize, tablet rotation), which rebuilds this subtree. Only the tab INDEX is kept;
  /// data reloads and permission checks are unchanged.
  static final ValueNotifier<int> selectedTab = ValueNotifier<int>(0);

  @override
  State<AcademyHomeScreen> createState() => _AcademyHomeScreenState();
}

class _AcademyHomeScreenState extends State<AcademyHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: AcademyHomeScreen.selectedTab.value.clamp(0, 2),
  )..addListener(() => AcademyHomeScreen.selectedTab.value = _tabs.index);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final feesAvailable = widget.feesAvailable;
    final manager = campusesWith(context, academyManage).isNotEmpty;
    if (!manager) {
      return Column(
        children: [
          const PageHeader(
            title: 'My batches',
            subtitle: 'Batches you currently teach',
          ),
          Expanded(
            child: ResultBannerHost(
              child: BatchesScreen(
                repository: repository,
                mine: true,
                feesAvailable: feesAvailable,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        const PageHeader(
          title: 'Academy',
          subtitle: 'Courses, batches, sessions and learners',
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Batches'),
            Tab(text: 'Courses'),
            Tab(text: 'Offerings'),
          ],
        ),
        Expanded(
          // Action outcomes from every tab appear inline above it.
          child: ResultBannerHost(
            child: TabBarView(
              controller: _tabs,
              children: [
                BatchesScreen(
                  repository: repository,
                  feesAvailable: feesAvailable,
                ),
                CoursesScreen(repository: repository),
                OfferingsScreen(repository: repository),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
