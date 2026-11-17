import 'package:flutter/material.dart';

String? scheduledPickupLabel(BuildContext context, Object? value) {
  if (value is! DateTime) return null;
  final local = value.toLocal();
  final formatter = MaterialLocalizations.of(context);
  final date = formatter.formatMediumDate(local);
  final time = formatter.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '$date, $time';
}
