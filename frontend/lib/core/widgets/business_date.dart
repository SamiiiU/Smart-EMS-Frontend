import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Human-readable form of a server BUSINESS date ("2026-10-14").
///
/// Business dates (attendance day, due date, remark day) are already in the
/// institution's own calendar (project rule 5: DATE in the tenant's timezone),
/// so they are parsed as a plain calendar date and never shifted through a
/// timezone. Formatted as a localized day-month-year (e.g. "Oct 14, 2026" in
/// English) — the year is kept so a remark from last session is never
/// mistaken for this one. Anything not in YYYY-MM-DD form is shown as received.
String formatBusinessDate(BuildContext context, String isoDate) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDate.trim());
  if (m == null) return isoDate;
  final date = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en';
  try {
    return DateFormat.yMMMd(locale).format(date);
  } on Object {
    // Date symbols for this locale are not loaded: English is still readable.
    return DateFormat.yMMMd('en').format(date);
  }
}
