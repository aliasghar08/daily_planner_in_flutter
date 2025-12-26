import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/add_medication_page.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:intl/intl.dart';

class MedicationListPage extends StatefulWidget {
  final MedicationManager medicationManager;

  const MedicationListPage({
    Key? key,
    required this.medicationManager,
  }) : super(key: key);

  @override
  State<MedicationListPage> createState() => _MedicationListPageState();
}

class _MedicationListPageState extends State<MedicationListPage> {
  List<Medication> _medications = [];
  List<MedicationSchedule> _schedules = [];
  List<MedicationIntake> _todaysIntakes = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

Future<void> _loadMedications() async {
  setState(() {
    _isLoading = true;
  });
  
  try {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    
    // Get current user ID
    final String? userId = _getCurrentUserId();
    
    if (userId == null) {
      // Handle not logged in state
      print('User not authenticated, loading local data only');
      _loadLocalDataOnly();
      return;
    }
    
    // Clear existing local data
    _medications.clear();
    
    // =============================================
    // PART 1: Fetch medications from user's collection
    // =============================================
    final medicationsSnapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('medications')
        .orderBy('createdAt', descending: true)
        .get();
    
    print('Loaded ${medicationsSnapshot.docs.length} medications for user $userId');
    
    // Convert Firebase documents to Medication objects
    for (final doc in medicationsSnapshot.docs) {
      try {
        final data = doc.data();
        final medication = Medication(
          medicationId: doc.id,
          name: data['name'] ?? 'Unknown',
          dosage: (data['dosage'] as num?)?.toDouble() ?? 0.0,
          unit: _parseDosageUnit(data['unit']),
          description: data['description'],
          color: data['color'] ?? '#3498db',
          icon: data['icon'] ?? '💊',
        );
        _medications.add(medication);
        
        // Add to local manager for immediate access
        widget.medicationManager.addMedication(medication);
      } catch (e) {
        print('Error parsing medication ${doc.id}: $e');
      }
    }
    
    // =============================================
    // PART 2: Fetch schedules from user's collection
    // =============================================
    final schedulesSnapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .get();
    
    print('Loaded ${schedulesSnapshot.docs.length} schedules for user $userId');
    
    // Clear existing schedules in local manager
    // You might need to add this method to MedicationManager:
    widget.medicationManager.schedules.clear();
    
    for (final doc in schedulesSnapshot.docs) {
      try {
        final data = doc.data();
        final medicationId = data['medicationId'];
        
        // Find the corresponding medication
        final medication = _medications.firstWhere(
          (med) => med.medicationId == medicationId,
          orElse: () {
            // Create a placeholder medication if not found
            return Medication(
              medicationId: medicationId,
              name: data['medicationName'] ?? 'Unknown Medication',
              dosage: 0.0,
              unit: DosageUnit.mg,
              color: '#3498db',
              icon: '💊',
            );
          },
        );
        
        // Parse schedule data
        final schedule = MedicationSchedule(
          scheduleId: doc.id,
          medication: medication,
          startDate: (data['startDate'] as Timestamp).toDate(),
          endDate: data['endDate'] != null 
              ? (data['endDate'] as Timestamp).toDate()
              : null,
          frequency: _parseFrequency(data['frequency']),
          timesPerDay: _parseTimesPerDay(data['timesPerDay']),
          daysOfWeek: List<int>.from(data['daysOfWeek'] ?? []),
          specificDates: _parseSpecificDates(data['specificDates']),
          instructions: data['instructions'],
          reminderMinutesBefore: data['reminderMinutesBefore'] ?? 15,
        );
        
        // Add to local manager
        widget.medicationManager.createSchedule(schedule);
      } catch (e) {
        print('Error parsing schedule ${doc.id}: $e');
      }
    }
    
    // =============================================
    // PART 3: Get today's intakes
    // =============================================
    // This will use the local manager which now has Firebase data
    _todaysIntakes = widget.medicationManager.getIntakesForDate(_selectedDate);
    
    // Sort intakes by scheduled time
    _todaysIntakes.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    
    // Optional: Load intakes from Firebase directly if you store them
    // You might store intakes in: users/{userId}/intakes
    await _loadIntakesFromFirebase(userId);
    
  } catch (e) {
    print('Error loading medications from Firebase: $e');
    
    // Fallback to local data if Firebase fails
    _loadLocalDataOnly();
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}

Future<void> _loadIntakesFromFirebase(String userId) async {
  try {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final firestore = FirebaseFirestore.instance;
    final intakesSnapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('intakes')
        .where('scheduledTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledTime', isLessThan: Timestamp.fromDate(endOfDay))
        .get();
    
    // Process intakes if you store them in Firebase
    // You would need to implement this based on your data structure
    for (final doc in intakesSnapshot.docs) {
      // Parse intake data here
    }
  } catch (e) {
    print('Error loading intakes from Firebase: $e');
    // It's okay if intakes aren't stored in Firebase yet
  }
}

// Helper for loading local data when Firebase fails
void _loadLocalDataOnly() {
  try {
    _medications = widget.medicationManager.medications;
    _schedules = widget.medicationManager.schedules;
    _todaysIntakes = widget.medicationManager.getIntakesForDate(_selectedDate);
    _todaysIntakes.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
  } catch (fallbackError) {
    print('Fallback also failed: $fallbackError');
  }
}

// Helper to get current user ID
String? _getCurrentUserId() {
  // Make sure you have imported firebase_auth
  // import 'package:firebase_auth/firebase_auth.dart';
  final user = FirebaseAuth.instance.currentUser;
  return user?.uid;
}

// =============================================
// HELPER FUNCTIONS for data parsing
// =============================================

DosageUnit _parseDosageUnit(String? unitString) {
  if (unitString == null) return DosageUnit.mg;
  
  switch (unitString.toLowerCase()) {
    case 'mg': return DosageUnit.mg;
    case 'mcg': return DosageUnit.mcg;
    case 'ml': return DosageUnit.ml;
    case 'tablet': return DosageUnit.tablet;
    case 'capsule': return DosageUnit.capsule;
    case 'drop': return DosageUnit.drop;
    case 'spray': return DosageUnit.spray;
    case 'puff': return DosageUnit.puff;
    default: return DosageUnit.mg;
  }
}

MedicationFrequency _parseFrequency(String? frequencyString) {
  if (frequencyString == null) return MedicationFrequency.daily;
  
  switch (frequencyString.toLowerCase()) {
    case 'daily': return MedicationFrequency.daily;
    case 'weekly': return MedicationFrequency.weekly;
    case 'monthly': return MedicationFrequency.monthly;
    case 'asneeded': 
    case 'as needed': return MedicationFrequency.asNeeded;
    case 'custom': return MedicationFrequency.custom;
    default: return MedicationFrequency.daily;
  }
}

List<TimeOfDay> _parseTimesPerDay(List<dynamic>? timesData) {
  final times = <TimeOfDay>[];
  
  if (timesData == null) return times;
  
  for (final timeData in timesData) {
    try {
      if (timeData is Map<String, dynamic>) {
        final hour = timeData['hour'] as int? ?? 0;
        final minute = timeData['minute'] as int? ?? 0;
        times.add(TimeOfDay(hour: hour, minute: minute));
      }
    } catch (e) {
      print('Error parsing time: $e');
    }
  }
  
  return times;
}

List<DateTime> _parseSpecificDates(List<dynamic>? datesData) {
  final dates = <DateTime>[];
  
  if (datesData == null) return dates;
  
  for (final dateData in datesData) {
    try {
      if (dateData is Timestamp) {
        dates.add(dateData.toDate());
      }
    } catch (e) {
      print('Error parsing date: $e');
    }
  }
  
  return dates;
}

// Optional: Load intakes directly from Firebase if you store them

  /// Parses a hex color string to a Color object
  Color _parseColor(String colorHex) {
    try {
      return Color(int.parse(colorHex.substring(1, 7), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.blue;
    }
  }

  /// Formats a TimeOfDay object to a readable string (e.g., "9:30 AM")
  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Formats a DateTime object to a time string (e.g., "9:30 AM")
  String _formatDateTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  /// Formats a DateTime object to a date string (e.g., "15/12/2023")
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Formats a DateTime object to a relative date string
  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inputDate = DateTime(date.year, date.month, date.day);
    
    final difference = inputDate.difference(today).inDays;
    
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    if (difference == -1) return 'Yesterday';
    if (difference > 1 && difference < 7) return DateFormat('EEEE').format(date);
    
    return _formatDate(date);
  }

  /// Converts MedicationFrequency enum to a display string
  String _getFrequencyDisplayName(MedicationFrequency frequency) {
    switch (frequency) {
      case MedicationFrequency.daily:
        return 'Daily';
      case MedicationFrequency.weekly:
        return 'Weekly';
      case MedicationFrequency.monthly:
        return 'Monthly';
      case MedicationFrequency.asNeeded:
        return 'As Needed';
      case MedicationFrequency.custom:
        return 'Custom Dates';
    }
  }

  /// Formats dosage with unit for display (e.g., "500 mg")
  String _getDosageDisplay(Medication medication) {
    final unit = medication.unit.toString().split('.').last;
    return '${medication.dosage} ${unit.replaceAll('_', ' ').toLowerCase()}';
  }

  /// Formats selected days indices to day names (e.g., "Mon, Wed, Fri")
  String _formatDays(List<int> days) {
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final selectedDays = days.map((day) => dayNames[day]).toList();
    return selectedDays.join(', ');
  }

  /// Gets the status color for a medication intake
  Color _getStatusColor(IntakeStatus status) {
    switch (status) {
      case IntakeStatus.taken:
        return Colors.green;
      case IntakeStatus.missed:
        return Colors.red;
      case IntakeStatus.skipped:
        return Colors.orange;
      case IntakeStatus.pending:
        return Colors.grey;
      case IntakeStatus.upcoming:
        // TODO: Handle this case.
        throw UnimplementedError();
    }
  }

  /// Gets the status icon for a medication intake
  IconData _getStatusIcon(IntakeStatus status) {
    switch (status) {
      case IntakeStatus.taken:
        return Icons.check_circle;
      case IntakeStatus.missed:
        return Icons.cancel;
      case IntakeStatus.skipped:
        return Icons.do_not_disturb;
      case IntakeStatus.pending:
        return Icons.access_time;
      case IntakeStatus.upcoming:
        // TODO: Handle this case.
        throw UnimplementedError();
    }
  }

  /// Gets the status text for a medication intake
  String _getStatusText(MedicationIntake intake) {
    switch (intake.status) {
      case IntakeStatus.taken:
        final timeDiff = intake.actualTime?.difference(intake.scheduledTime);
        if (timeDiff != null && timeDiff.inMinutes > 0) {
          return 'Taken ${timeDiff.inMinutes} min late';
        } else if (timeDiff != null && timeDiff.inMinutes < 0) {
          return 'Taken ${timeDiff.inMinutes.abs()} min early';
        } else {
          return 'Taken on time';
        }
      case IntakeStatus.missed:
        return 'Missed';
      case IntakeStatus.skipped:
        return 'Skipped';
      case IntakeStatus.pending:
        return 'Pending';
      case IntakeStatus.upcoming:
        // TODO: Handle this case.
        throw UnimplementedError();
    }
  }

  /// Marks a medication intake as taken
  void _markIntakeAsTaken(MedicationIntake intake) {
    final updatedIntake = intake.markTaken();
    widget.medicationManager.updateIntake(updatedIntake);
    _loadMedications();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Marked ${intake.schedule.medication.name} as taken'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Marks a medication intake as missed
  void _markIntakeAsMissed(MedicationIntake intake) {
    final updatedIntake = intake.markMissed();
    widget.medicationManager.updateIntake(updatedIntake);
    _loadMedications();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Marked ${intake.schedule.medication.name} as missed'),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Marks a medication intake as skipped
  void _markIntakeAsSkipped(MedicationIntake intake) {
    final updatedIntake = intake.markSkipped();
    widget.medicationManager.updateIntake(updatedIntake);
    _loadMedications();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Marked ${intake.schedule.medication.name} as skipped'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  /// Shows a dialog to update intake status
  void _showUpdateIntakeDialog(MedicationIntake intake) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update ${intake.schedule.medication.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scheduled for ${_formatDateTime(intake.scheduledTime)}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Dosage: ${_getDosageDisplay(intake.schedule.medication)}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            const Text('Update status:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (intake.status != IntakeStatus.taken)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _markIntakeAsTaken(intake);
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Mark as Taken'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          if (intake.status != IntakeStatus.missed)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _markIntakeAsMissed(intake);
              },
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Mark as Missed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          if (intake.status != IntakeStatus.skipped)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _markIntakeAsSkipped(intake);
              },
              icon: const Icon(Icons.do_not_disturb, size: 18),
              label: const Text('Mark as Skipped'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  /// Shows date picker to view intakes for a specific date
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadMedications();
    }
  }

  /// Builds today's schedule section
  Widget _buildTodaysSchedule() {
    if (_todaysIntakes.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(
              Icons.calendar_today,
              size: 48,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 12),
            const Text(
              'No medications scheduled for today',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Date selector
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatRelativeDate(_selectedDate),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: _selectDate,
                tooltip: 'Select date',
              ),
            ],
          ),
        ),
        
        // Today's intakes list
        ..._todaysIntakes.map((intake) => _buildIntakeCard(intake)).toList(),
      ],
    );
  }

  /// Builds an intake card widget
  Widget _buildIntakeCard(MedicationIntake intake) {
    final isOverdue = intake.status == IntakeStatus.pending &&
        intake.scheduledTime.isBefore(DateTime.now());
    final medication = intake.schedule.medication;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _getStatusColor(intake.status).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showUpdateIntakeDialog(intake),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 8,
                height: 40,
                decoration: BoxDecoration(
                  color: _getStatusColor(intake.status),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              
              // Medication icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _parseColor(medication.color).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    medication.icon,
                    style: TextStyle(
                      fontSize: 20,
                      color: _parseColor(medication.color),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
              // Medication info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getDosageDisplay(medication),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDateTime(intake.scheduledTime),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (intake.actualTime != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDateTime(intake.actualTime!),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(intake.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStatusIcon(intake.status),
                      size: 16,
                      color: _getStatusColor(intake.status),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getStatusText(intake),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _getStatusColor(intake.status),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the medication card widget (kept from original)
  Widget _buildMedicationCard(Medication medication) {
    final schedules = _schedules
        .where((schedule) => schedule.medication.medicationId == medication.medicationId)
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with icon and name (same as before)
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _parseColor(medication.color),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      medication.icon,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medication.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getDosageDisplay(medication),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    // Handle medication actions
                    if (value == 'edit') {
                      _editMedication(medication, schedules.isNotEmpty ? schedules.first : null);
                    } else if (value == 'delete') {
                      _deleteMedication(medication);
                    }
                  },
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Today's intakes for this medication
            _buildMedicationTodaysIntakes(medication),

            // Schedules section (same as before)
            if (schedules.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Schedules:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...schedules.map((schedule) => _buildScheduleTile(schedule)),
            ],

            // No schedules message
            if (schedules.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No schedules set. Tap edit to add a schedule.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds today's intakes for a specific medication
  Widget _buildMedicationTodaysIntakes(Medication medication) {
    final todaysIntakes = _todaysIntakes
        .where((intake) => intake.schedule.medication.medicationId == medication.medicationId)
        .toList();

    if (todaysIntakes.isEmpty) {
      return Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          "Today's Doses:",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...todaysIntakes.map((intake) => _buildIntakeMiniCard(intake)).toList(),
      ],
    );
  }

  /// Builds a mini intake card for medication detail view
  Widget _buildIntakeMiniCard(MedicationIntake intake) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getStatusColor(intake.status).withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getStatusColor(intake.status).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            _getStatusIcon(intake.status),
            size: 16,
            color: _getStatusColor(intake.status),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDateTime(intake.scheduledTime),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _getStatusText(intake),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, size: 20),
            onPressed: () => _showUpdateIntakeDialog(intake),
          ),
        ],
      ),
    );
  }

  /// Builds a schedule tile widget (same as before, just shortened for brevity)
  Widget _buildScheduleTile(MedicationSchedule schedule) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Schedule info (same as before)
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                _getFrequencyDisplayName(schedule.frequency),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          // Times (same as before)
          if (schedule.timesPerDay.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: schedule.timesPerDay.map((time) {
                return Chip(
                  label: Text(
                    _formatTime(time),
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: Colors.blue[50],
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],

          // Date range (same as before)
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.date_range,
                size: 14,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                'From ${_formatDate(schedule.startDate)}${schedule.endDate != null ? ' to ${_formatDate(schedule.endDate!)}' : ' (no end date)'}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Handles medication actions (same as before)
  void _editMedication(Medication medication, MedicationSchedule? schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddMedicationPage(
          medicationManager: widget.medicationManager,
          existingMedication: medication,
          existingSchedule: schedule,
        ),
      ),
    ).then((_) => _loadMedications());
  }

  /// Shows confirmation dialog and deletes medication (same as before)
  // void _deleteMedication(Medication medication) {
  //   showDialog(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       title: const Text('Delete Medication'),
  //       content: Text('Are you sure you want to delete "${medication.name}"? This will also delete all associated schedules and intake records.'),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context),
  //           child: const Text('Cancel'),
  //         ),
  //         TextButton(
  //           onPressed: () {
  //             widget.medicationManager.deleteMedication(medication.medicationId!);
  //             _loadMedications();
  //             Navigator.pop(context);
  //             ScaffoldMessenger.of(context).showSnackBar(
  //               SnackBar(
  //                 content: Text('"${medication.name}" deleted successfully'),
  //                 backgroundColor: Colors.red,
  //               ),
  //             );
  //           },
  //           child: const Text(
  //             'Delete',
  //             style: TextStyle(color: Colors.red),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  /// Shows confirmation dialog and deletes medication from both local and Firebase
Future<void> _deleteMedication(Medication medication) async {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Medication'),
      content: Text('Are you sure you want to delete "${medication.name}"? This will also delete all associated schedules and intake records.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await _deleteMedicationFromFirebase(medication);
          },
          child: const Text(
            'Delete',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );
}

/// Deletes medication from Firebase and local storage
Future<void> _deleteMedicationFromFirebase(Medication medication) async {
  final String? userId = _getCurrentUserId();
  
  if (userId == null) {
    // If not authenticated, only delete locally
    widget.medicationManager.deleteMedication(medication.medicationId!);
    _loadMedications();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${medication.name}" deleted locally'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }
  
  try {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final String medicationId = medication.medicationId!;
    
    // First, delete the medication document
    await firestore
        .collection('users')
        .doc(userId)
        .collection('medications')
        .doc(medicationId)
        .delete();
    
    print('Deleted medication $medicationId from Firebase');
    
    // Delete associated schedules
    final schedulesQuery = await firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .where('medicationId', isEqualTo: medicationId)
        .get();
    
    // Delete all schedule documents
    final batch = firestore.batch();
    for (final doc in schedulesQuery.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    
    print('Deleted ${schedulesQuery.docs.length} schedules for medication $medicationId');
    
    // Delete associated intakes (if you store them in Firebase)
    await _deleteIntakesForMedication(userId, medicationId);
    
    // Finally, delete from local manager
    widget.medicationManager.deleteMedication(medicationId);
    
    // Refresh the UI
    _loadMedications();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${medication.name}" deleted successfully'),
        backgroundColor: Colors.red,
      ),
    );
    
  } catch (e) {
    print('Error deleting medication from Firebase: $e');
    
    // Fallback: delete locally if Firebase fails
    widget.medicationManager.deleteMedication(medication.medicationId!);
    _loadMedications();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error deleting from cloud, removed locally only'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

/// Deletes intakes associated with a medication
Future<void> _deleteIntakesForMedication(String userId, String medicationId) async {
  try {
    final firestore = FirebaseFirestore.instance;
    
    // If you store intakes in Firebase, delete them
    final intakesQuery = await firestore
        .collection('users')
        .doc(userId)
        .collection('intakes')
        .where('medicationId', isEqualTo: medicationId)
        .get();
    
    if (intakesQuery.docs.isNotEmpty) {
      final batch = firestore.batch();
      for (final doc in intakesQuery.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('Deleted ${intakesQuery.docs.length} intakes for medication $medicationId');
    }
  } catch (e) {
    print('Error deleting intakes: $e');
    // Continue even if intakes deletion fails
  }
}

  /// Navigates to add new medication page (same as before)
  void _addNewMedication() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddMedicationPage(
          medicationManager: widget.medicationManager,
        ),
      ),
    ).then((_) => _loadMedications());
  }

  /// Builds the empty state widget when no medications are added
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.medication_outlined,
              size: 100,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 24),
            const Text(
              'No Medications Added',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You haven\'t added any medications yet.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the + button below to add your first medication.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _addNewMedication,
              icon: const Icon(Icons.add),
              label: const Text('Add First Medication'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the loading state widget
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading medications...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Medications'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
            tooltip: 'Select date',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMedications,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _medications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadMedications,
                  color: Theme.of(context).primaryColor,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 80),
                    children: [
                      // Today's schedule section
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Today\'s Schedule',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTodaysSchedule(),
                      
                      // All medications section
                      const SizedBox(height: 24),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'All Medications',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._medications.map((medication) => _buildMedicationCard(medication)).toList(),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewMedication,
        icon: const Icon(Icons.add),
        label: const Text('Add Medication'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}