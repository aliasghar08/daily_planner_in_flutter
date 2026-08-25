void main() {
  final completedAt = DateTime.parse("2026-08-25 23:47:21").toUtc();
  final now = DateTime.parse("2026-08-25 23:48:00").toUtc();

  print("CompletedAt UTC: $completedAt");
  print("Now UTC: $now");

  final shouldReset = !(completedAt.year == now.year &&
      completedAt.month == now.month &&
      completedAt.day == now.day);
      
  print("Should reset: $shouldReset");
}
