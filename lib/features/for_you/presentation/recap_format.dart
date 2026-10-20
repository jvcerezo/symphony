/// Number and time wording shared by the recap screen and its share cards.
library;

String formatCount(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String formatHour(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';

/// What kind of listener someone is, from the hour they listen most.
String listenerKind(int hour) {
  if (hour >= 5 && hour < 12) return 'an early riser';
  if (hour >= 12 && hour < 18) return 'an afternoon listener';
  if (hour >= 18 && hour < 23) return 'an evening listener';
  return 'a night owl';
}
