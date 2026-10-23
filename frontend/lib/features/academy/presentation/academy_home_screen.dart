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
class AcademyHomeScreen extends StatelessWidget {
  const AcademyHomeScreen({
    required this.repository,
    this.feesAvailable = false,
    super.key,
  });

  final AcademyRepository repository;

  /// True when this account holds fee.manage somewhere (batch fee panel).
  final bool feesAvailable;

  @override
  Widget build(BuildContext context) {
    final manager = campusesWith(context, academyManage).isNotEmpty;
    if (!manager) {
      return Column(
        children: [
          const PageHeader(
            title: 'My batches',
            subtitle: 'Batches you currently teach',
          ),
          Expanded(
            child: BatchesScreen(
              repository: repository,
              mine: true,
              feesAvailable: feesAvailable,
            ),
          ),
        ],
      );
    }
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const PageHeader(
            title: 'Academy',
            subtitle: 'Courses, batches, sessions and learners',
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Batches'),
              Tab(text: 'Courses'),
              Tab(text: 'Offerings'),
            ],
          ),
          Expanded(
            child: TabBarView(
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
        ],
      ),
    );
  }
}
