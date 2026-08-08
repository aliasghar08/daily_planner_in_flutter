import 'dart:async';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';
import 'package:flutter/foundation.dart';

class IntakeGeneratorService {
  final MedicationManager medicationManager;
  Timer? _dailyTimer;
  Timer? _hourlyTimer;

  IntakeGeneratorService(this.medicationManager);

  void start() {
    debugPrint('IntakeGeneratorService: Starting...');

    // Generate intakes immediately
    medicationManager.ensureTodaysIntakes();
    medicationManager.regenerateIntakes();

    // Check every hour for new intakes and missed intakes
    _hourlyTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      debugPrint('IntakeGeneratorService: Hourly check...');
      medicationManager.ensureTodaysIntakes();
      medicationManager.checkAndMarkMissedIntakes();

      // If it's near midnight, regenerate for tomorrow
      final now = DateTime.now();
      if (now.hour == 23) {
        medicationManager.regenerateIntakes();
      }
    });

    // Reset at circadian cutoff (4:00 AM) daily
    _scheduleCircadianReset();

    debugPrint('IntakeGeneratorService: Started successfully');
  }

  void _scheduleCircadianReset() {
    final now = DateTime.now();
    DateTime nextReset = DateTime(now.year, now.month, now.day, 4, 0);
    if (now.isAfter(nextReset) || now.isAtSameMomentAs(nextReset)) {
      nextReset = nextReset.add(const Duration(days: 1));
    }
    final durationUntilReset = nextReset.difference(now);

    debugPrint('IntakeGeneratorService: Next circadian reset (4 AM) in $durationUntilReset');

    _dailyTimer = Timer(durationUntilReset, () {
      debugPrint('IntakeGeneratorService: 4 AM Circadian reset triggered');

      // Regenerate intakes for new logical day
      medicationManager.regenerateIntakes();
      medicationManager.checkAndMarkMissedIntakes();

      // Schedule next 4 AM reset
      _scheduleCircadianReset();
    });
  }

  void stop() {
    debugPrint('IntakeGeneratorService: Stopping...');
    _dailyTimer?.cancel();
    _hourlyTimer?.cancel();
    debugPrint('IntakeGeneratorService: Stopped');
  }

  // Manual trigger for testing
  void forceRegenerate() {
    debugPrint('IntakeGeneratorService: Force regenerating intakes');
    medicationManager.regenerateIntakes();
    medicationManager.checkAndMarkMissedIntakes();
  }
}