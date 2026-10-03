// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/core/network/api_meta.dart';
import 'package:campus_koethen/features/timetable/application/timetable_providers.dart';
import 'package:campus_koethen/features/timetable/data/timetable_models.dart';

class FixedTimetableGroupSearchController
    extends TimetableGroupSearchController {
  FixedTimetableGroupSearchController(this.fixed) : super('');

  final TimetableGroupSearchState fixed;

  @override
  Future<TimetableGroupSearchState> build() async => fixed;
}

TimetableGroupSearchState fixedTimetableGroupSearch(
  List<TimetableGroup> groups,
) => TimetableGroupSearchState(
  groups: groups,
  page: 1,
  totalPages: 1,
  meta: ApiMeta.empty,
);
