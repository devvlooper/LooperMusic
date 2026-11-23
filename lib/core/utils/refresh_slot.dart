/// Which part of the day [t] is in, unique across days: morning from 06:00,
/// afternoon from 12:00, evening from 18:00 until 06:00 the next day.
/// Automatic refreshes run at most once per slot.
int refreshSlot(DateTime t) {
  final overnight = t.hour < 6;
  final day = DateTime.utc(t.year, t.month, t.day - (overnight ? 1 : 0));
  final part = overnight || t.hour >= 18 ? 2 : (t.hour < 12 ? 0 : 1);
  return day.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay * 3 + part;
}
