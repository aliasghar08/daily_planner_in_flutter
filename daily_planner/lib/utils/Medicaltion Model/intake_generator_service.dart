// lib/services/intake_generator_service.dart
import 'dart:async';
// import 'package:daily_planner/services/medication_manager.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';

class IntakeGeneratorService {
  final MedicationManager medicationManager;
  Timer? _dailyTimer;
  Timer? _hourlyTimer;

  IntakeGeneratorService(this.medicationManager);

  void start() {
    print('IntakeGeneratorService: Starting...');
    
    // Generate intakes immediately
    medicationManager.ensureTodaysIntakes();
    medicationManager.regenerateIntakes();
    
    // Check every hour for new intakes and missed intakes
    _hourlyTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      print('IntakeGeneratorService: Hourly check...');
      medicationManager.ensureTodaysIntakes();
      medicationManager.checkAndMarkMissedIntakes();
      
      // If it's near midnight, regenerate for tomorrow
      final now = DateTime.now();
      if (now.hour == 23) {
        medicationManager.regenerateIntakes();
      }
    });
    
    // Reset at midnight daily
    _scheduleMidnightReset();
    
    print('IntakeGeneratorService: Started successfully');
  }

  void _scheduleMidnightReset() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final durationUntilMidnight = midnight.difference(now);
    
    print('IntakeGeneratorService: Next midnight reset in $durationUntilMidnight');
    
    _dailyTimer = Timer(durationUntilMidnight, () {
      print('IntakeGeneratorService: Midnight reset triggered');
      
      // Regenerate intakes for new day
      medicationManager.regenerateIntakes();
      medicationManager.checkAndMarkMissedIntakes();
      
      // Schedule next midnight reset
      _scheduleMidnightReset();
    });
  }

  void stop() {
    print('IntakeGeneratorService: Stopping...');
    _dailyTimer?.cancel();
    _hourlyTimer?.cancel();
    print('IntakeGeneratorService: Stopped');
  }

  // Manual trigger for testing
  void forceRegenerate() {
    print('IntakeGeneratorService: Force regenerating intakes');
    medicationManager.regenerateIntakes();
    medicationManager.checkAndMarkMissedIntakes();
  }
}