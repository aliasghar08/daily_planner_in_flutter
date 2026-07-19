import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MedicationDetailPage extends StatefulWidget {
  final Medication medication;
  final MedicationManager medicationManager;

  const MedicationDetailPage({
    Key? key,
    required this.medication,
    required this.medicationManager,
  }) : super(key: key);

  @override
  State<MedicationDetailPage> createState() => _MedicationDetailPageState();
}

class _MedicationDetailPageState extends State<MedicationDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MedicationSchedule> _schedules = [];
  List<MedicationIntake> _intakeHistory = [];
  List<MedicationIntake> _filteredIntakeHistory = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  DateTime _selectedHistoryDate = DateTime.now();
  IntakeStatus? _selectedStatusFilter;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _userId = _auth.currentUser?.uid;
    _loadMedicationData();
  }

  @override
  void didUpdateWidget(MedicationDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.medication != widget.medication) {
      _loadMedicationData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMedicationData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load from local manager
      final allIntakes = widget.medicationManager.allIntakes;
      
      // Load schedules for this medication
      _schedules = widget.medicationManager.schedules
          .where((schedule) =>
              schedule.medication.medicationId ==
              widget.medication.medicationId)
          .toList();

      // Load intake history for this medication
      _intakeHistory = allIntakes
          .where((intake) =>
              intake.schedule.medication.medicationId ==
              widget.medication.medicationId)
          .toList();

      // Sort intake history by date (newest first)
      _intakeHistory.sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));
      
      // Apply initial filter
      _applyFilters();

      // If user is authenticated, sync with Firebase
      if (_userId != null) {
        await _syncWithFirebase();
        await _loadIntakesFromFirebase();
      }

      // Calculate statistics
      _calculateStats();

    } catch (e) {
      print('Error loading medication details: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _syncWithFirebase() async {
    try {
      // Upload medication to Firebase
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('medications')
          .doc(widget.medication.medicationId)
          .set(widget.medication.toMap(), SetOptions(merge: true));

      // Upload intakes to Firebase
      for (final intake in _intakeHistory) {
        await _updateIntakeInFirebase(intake);
      }

      print('Synced medication data with Firebase');
    } catch (e) {
      print('Error syncing with Firebase: $e');
    }
  }

  Future<void> _loadIntakesFromFirebase() async {
    if (_userId == null) return;

    try {
      final intakesSnapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('intakes')
          .where('medicationId', isEqualTo: widget.medication.medicationId)
          .orderBy('scheduledTime', descending: true)
          .get();

      // Merge Firebase intakes with local ones
      for (final doc in intakesSnapshot.docs) {
        final firebaseIntake = MedicationIntake.fromMap(doc.data());
        
        // Check if intake exists locally
        final existingIndex = _intakeHistory.indexWhere(
          (intake) => intake.intakeId == firebaseIntake.intakeId
        );
        
        if (existingIndex >= 0) {
          // Update local intake with Firebase data if it's newer
          _intakeHistory[existingIndex] = firebaseIntake;
        } else {
          // Add Firebase intake to local list
          _intakeHistory.add(firebaseIntake);
        }
      }
      
      // Re-sort and re-filter
      _intakeHistory.sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));
      _applyFilters();
      
      setState(() {});

    } catch (e) {
      print('Error loading intakes from Firebase: $e');
    }
  }

  Future<void> _updateIntakeInFirebase(MedicationIntake intake) async {
    if (_userId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('intakes')
          .doc(intake.intakeId)
          .set({
        ...intake.toMap(),
        'medicationId': widget.medication.medicationId,
        'scheduleId': intake.schedule.scheduleId,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      
      // Update adherence record
      await _updateAdherenceRecord(intake);
      
    } catch (e) {
      print('Error updating intake in Firebase: $e');
    }
  }

  Future<void> _updateAdherenceRecord(MedicationIntake intake) async {
    if (_userId == null) return;

    try {
      final dateKey = DateFormat('yyyy-MM-dd').format(intake.scheduledTime);
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('adherence')
          .doc('${widget.medication.medicationId}_$dateKey')
          .set({
        'medicationId': widget.medication.medicationId,
        'date': dateKey,
        'status': intake.status.name,
        'scheduledTime': intake.scheduledTime.toIso8601String(),
        'actualTime': intake.actualTime?.toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating adherence record: $e');
    }
  }

  void _calculateStats() {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    
    // Filter intakes from last 30 days
    final recentIntakes = _intakeHistory.where((intake) => 
        intake.scheduledTime.isAfter(thirtyDaysAgo)).toList();
    
    final totalScheduled = recentIntakes.length;
    final takenIntakes = recentIntakes.where((intake) => 
        intake.status == IntakeStatus.taken).length;
    final missedIntakes = recentIntakes.where((intake) => 
        intake.status == IntakeStatus.missed).length;
    final skippedIntakes = recentIntakes.where((intake) => 
        intake.status == IntakeStatus.skipped).length;
    
    final adherenceRate = totalScheduled > 0 
        ? (takenIntakes / totalScheduled * 100).round()
        : 0;

    // Calculate streak
    int currentStreak = 0;
    DateTime currentDate = DateTime.now();
    bool streakActive = true;
    
    while (streakActive) {
      final dateIntakes = recentIntakes.where((intake) =>
          intake.scheduledTime.year == currentDate.year &&
          intake.scheduledTime.month == currentDate.month &&
          intake.scheduledTime.day == currentDate.day).toList();
      
      if (dateIntakes.isEmpty) {
        streakActive = false;
        break;
      }
      
      final anyTaken = dateIntakes.any((intake) => 
          intake.status == IntakeStatus.taken);
      
      if (anyTaken) {
        currentStreak++;
        currentDate = currentDate.subtract(const Duration(days: 1));
      } else {
        streakActive = false;
      }
    }

    // Get most common intake time
    Map<int, int> hourFrequency = {};
    for (final intake in recentIntakes.where((i) => i.status == IntakeStatus.taken)) {
      if (intake.actualTime != null) {
        final hour = intake.actualTime!.hour;
        hourFrequency[hour] = (hourFrequency[hour] ?? 0) + 1;
      }
    }

    int? mostCommonHour;
    int maxFrequency = 0;
    hourFrequency.forEach((hour, frequency) {
      if (frequency > maxFrequency) {
        maxFrequency = frequency;
        mostCommonHour = hour;
      }
    });

    // Get today's intakes for stats
    final todaysIntakes = widget.medicationManager.getIntakesForDate(DateTime.now())
        .where((intake) => intake.schedule.medication.medicationId == widget.medication.medicationId)
        .toList();
    
    final pendingToday = todaysIntakes.where((intake) => intake.status == IntakeStatus.pending).length;
    final takenToday = todaysIntakes.where((intake) => intake.status == IntakeStatus.taken).length;
    final missedToday = todaysIntakes.where((intake) => intake.status == IntakeStatus.missed).length;

    _stats = {
      'adherenceRate': adherenceRate,
      'currentStreak': currentStreak,
      'totalScheduled': totalScheduled,
      'taken': takenIntakes,
      'missed': missedIntakes,
      'skipped': skippedIntakes,
      'mostCommonHour': mostCommonHour,
      'firstIntakeDate': _intakeHistory.isNotEmpty 
          ? _intakeHistory.last.scheduledTime 
          : null,
      'lastIntakeDate': _intakeHistory.isNotEmpty 
          ? _intakeHistory.first.scheduledTime 
          : null,
      'pendingToday': pendingToday,
      'takenToday': takenToday,
      'missedToday': missedToday,
    };
  }

  void _applyFilters() {
    List<MedicationIntake> filtered = _intakeHistory;
    
    // Filter by date
    filtered = filtered.where((intake) =>
        intake.scheduledTime.year == _selectedHistoryDate.year &&
        intake.scheduledTime.month == _selectedHistoryDate.month &&
        intake.scheduledTime.day == _selectedHistoryDate.day).toList();
    
    // Filter by status if selected
    if (_selectedStatusFilter != null) {
      filtered = filtered.where((intake) => 
          intake.status == _selectedStatusFilter).toList();
    }
    
    setState(() {
      _filteredIntakeHistory = filtered;
    });
  }

  String? _getCurrentUserId() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  Color _parseColor(String colorHex) {
    try {
      return Color(int.parse(colorHex.substring(1, 7), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.blue;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _getDosageDisplay(Medication medication) {
    final unit = medication.unit.toString().split('.').last;
    return '${medication.dosage} ${unit.replaceAll('_', ' ').toLowerCase()}';
  }

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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _parseColor(widget.medication.color).withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: _parseColor(widget.medication.color),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    widget.medication.icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.medication.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getDosageDisplay(widget.medication),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[700],
                      ),
                    ),
                    if (widget.medication.description != null &&
                        widget.medication.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.medication.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                icon: Icons.timeline,
                value: '${_stats['adherenceRate'] ?? 0}%',
                label: 'Adherence',
                color: Colors.green,
              ),
              _buildStatItem(
                icon: Icons.local_fire_department,
                value: '${_stats['currentStreak'] ?? 0}',
                label: 'Day Streak',
                color: Colors.orange,
              ),
              _buildStatItem(
                icon: Icons.today,
                value: '${_stats['takenToday'] ?? 0}/${(_stats['takenToday'] ?? 0) + (_stats['pendingToday'] ?? 0) + (_stats['missedToday'] ?? 0)}',
                label: 'Today',
                color: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Icon(icon, color: color, size: 24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleCard(MedicationSchedule schedule) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  _getFrequencyDisplayName(schedule.frequency),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (schedule.timesPerDay.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _getNextIntakeTime(schedule),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editSchedule(schedule),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (schedule.timesPerDay.isNotEmpty) ...[
              const Text(
                'Times:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: schedule.timesPerDay.map((time) {
                  return Chip(
                    label: Text(_formatTime(time)),
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'From ${_formatDate(schedule.startDate)}${schedule.endDate != null ? ' to ${_formatDate(schedule.endDate!)}' : ' (no end date)'}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (schedule.daysOfWeek.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Days: ${_formatDaysOfWeek(schedule.daysOfWeek)}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            if (schedule.instructions != null &&
                schedule.instructions!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Instructions: ${schedule.instructions!}',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildTodayIntakesForSchedule(schedule),
          ],
        ),
      ),
    );
  }

  String _getNextIntakeTime(MedicationSchedule schedule) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final todaysIntakes = schedule.generateIntakesForDate(today);
    if (todaysIntakes.isEmpty) return 'No intakes today';
    
    for (final intake in todaysIntakes) {
      if (intake.scheduledTime.isAfter(now)) {
        return 'Next: ${_formatDateTime(intake.scheduledTime)}';
      }
    }
    
    return 'None today';
  }

  Widget _buildTodayIntakesForSchedule(MedicationSchedule schedule) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todaysIntakes = schedule.generateIntakesForDate(today);
    
    if (todaysIntakes.isEmpty) return const SizedBox();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Intakes:",
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: todaysIntakes.map((intake) {
            return Chip(
              label: Text(
                _formatDateTime(intake.scheduledTime),
                style: TextStyle(
                  color: _getStatusColor(intake.status),
                  fontSize: 12,
                ),
              ),
              backgroundColor: _getStatusColor(intake.status).withOpacity(0.1),
              avatar: Icon(
                _getStatusIcon(intake.status),
                size: 14,
                color: _getStatusColor(intake.status),
              ),
              onDeleted: intake.status == IntakeStatus.pending ? () {
                _handleIntakeAction(intake);
              } : null,
              deleteIcon: intake.status == IntakeStatus.pending 
                  ? const Icon(Icons.check, size: 14)
                  : null,
            );
          }).toList(),
        ),
      ],
    );
  }

  String _formatDaysOfWeek(List<int> days) {
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final selectedDays = days.map((day) => dayNames[day]).toList();
    return selectedDays.join(', ');
  }

  Widget _buildIntakeHistoryItem(MedicationIntake intake) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _getStatusColor(intake.status).withOpacity(0.1),
          ),
          child: Center(
            child: Icon(
              _getStatusIcon(intake.status),
              color: _getStatusColor(intake.status),
              size: 20,
            ),
          ),
        ),
        title: Text(
          _formatDateTime(intake.scheduledTime),
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getStatusText(intake),
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (intake.actualTime != null) ...[
              const SizedBox(height: 2),
              Text(
                'Taken at ${_formatDateTime(intake.actualTime!)}',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                ),
              ),
            ],
            if (intake.notes != null && intake.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Note: ${intake.notes!}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatDate(intake.scheduledTime),
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 4),
            if (intake.status == IntakeStatus.pending && 
                intake.scheduledTime.isAfter(DateTime.now()))
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  icon: const Icon(Icons.check, size: 12),
                  padding: EdgeInsets.zero,
                  onPressed: () => _handleIntakeAction(intake),
                ),
              ),
          ],
        ),
        onTap: () => _showIntakeDetails(intake),
      ),
    );
  }

  Color _getStatusColor(IntakeStatus status) {
    switch (status) {
      case IntakeStatus.taken:
        return Colors.green;
      case IntakeStatus.missed:
        return Colors.red;
      case IntakeStatus.skipped:
        return Colors.orange;
      case IntakeStatus.pending:
        return Colors.blue;
      case IntakeStatus.upcoming:
        return Colors.purple;
    }
  }

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
        return Icons.upcoming;
    }
  }

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
        return 'Upcoming';
    }
  }

  Future<void> _handleIntakeAction(MedicationIntake intake) async {
    final action = await showModalBottomSheet<IntakeStatus>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.check, color: Colors.green),
                title: const Text('Mark as Taken'),
                onTap: () => Navigator.pop(context, IntakeStatus.taken),
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: const Text('Mark as Missed'),
                onTap: () => Navigator.pop(context, IntakeStatus.missed),
              ),
              ListTile(
                leading: const Icon(Icons.do_not_disturb, color: Colors.orange),
                title: const Text('Mark as Skipped'),
                onTap: () => Navigator.pop(context, IntakeStatus.skipped),
              ),
            ],
          ),
        );
      },
    );

    if (action != null) {
      MedicationIntake updatedIntake;
      
      switch (action) {
        case IntakeStatus.taken:
          updatedIntake = intake.markTaken();
          break;
        case IntakeStatus.missed:
          updatedIntake = intake.markMissed();
          break;
        case IntakeStatus.skipped:
          updatedIntake = intake.markSkipped();
          break;
        default:
          return;
      }
      
      // Update in medication manager
      widget.medicationManager.updateIntake(updatedIntake);
      
      // Update in Firebase
      await _updateIntakeInFirebase(updatedIntake);
      
      // Refresh data
      _loadMedicationData();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Intake marked as ${action.name}'),
          backgroundColor: _getStatusColor(action),
        ),
      );
    }
  }

  void _showIntakeDetails(MedicationIntake intake) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Intake Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Medication: ${intake.schedule.medication.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Scheduled: ${_formatDateTime(intake.scheduledTime)}'),
              Text('Date: ${_formatDate(intake.scheduledTime)}'),
              const SizedBox(height: 8),
              Text('Status: ${_getStatusText(intake)}'),
              if (intake.actualTime != null)
                Text('Actual Time: ${_formatDateTime(intake.actualTime!)}'),
              if (intake.notes != null && intake.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(intake.notes!),
              ],
              if (intake.dosageTaken != null) ...[
                const SizedBox(height: 8),
                Text('Dosage Taken: ${intake.dosageTaken} ${intake.schedule.medication.unit.name}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (intake.status == IntakeStatus.pending)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _handleIntakeAction(intake);
              },
              child: const Text('Mark'),
            ),
        ],
      ),
    );
  }

  void _editSchedule(MedicationSchedule schedule) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit schedule feature coming soon')),
    );
  }

  Future<void> _deleteMedication() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Medication'),
        content: Text(
            'Are you sure you want to delete "${widget.medication.name}"? This will also delete all associated schedules and intake records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Delete from medication manager
      widget.medicationManager.deleteMedication(widget.medication.medicationId);
      
      // Delete from Firebase if user is authenticated
      if (_userId != null) {
        try {
          // Delete medication from Firebase
          await _firestore
              .collection('users')
              .doc(_userId)
              .collection('medications')
              .doc(widget.medication.medicationId)
              .delete();
          
          // Delete associated intakes from Firebase
          final intakesSnapshot = await _firestore
              .collection('users')
              .doc(_userId)
              .collection('intakes')
              .where('medicationId', isEqualTo: widget.medication.medicationId)
              .get();
          
          for (final doc in intakesSnapshot.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          print('Error deleting from Firebase: $e');
        }
      }
      
      // Navigate back
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${widget.medication.name}" deleted successfully'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportHistory() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export feature coming soon')),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Medication Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailItem(
                  icon: Icons.medication,
                  label: 'Dosage',
                  value: _getDosageDisplay(widget.medication),
                ),
                _buildDetailItem(
                  icon: Icons.color_lens,
                  label: 'Color',
                  value: '',
                  colorWidget: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _parseColor(widget.medication.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                if (widget.medication.description != null &&
                    widget.medication.description!.isNotEmpty)
                  _buildDetailItem(
                    icon: Icons.description,
                    label: 'Description',
                    value: widget.medication.description!,
                  ),
                if (_stats['firstIntakeDate'] != null)
                  _buildDetailItem(
                    icon: Icons.date_range,
                    label: 'First Taken',
                    value: _formatDate(_stats['firstIntakeDate'] as DateTime),
                  ),
                if (_stats['mostCommonHour'] != null)
                  _buildDetailItem(
                    icon: Icons.access_time,
                    label: 'Most Common Time',
                    value: '${_stats['mostCommonHour']}:00',
                  ),
                const SizedBox(height: 24),
                const Text(
                  "Today's Summary",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMiniStat(
                      value: '${_stats['takenToday'] ?? 0}',
                      label: 'Taken',
                      color: Colors.green,
                    ),
                    _buildMiniStat(
                      value: '${_stats['pendingToday'] ?? 0}',
                      label: 'Pending',
                      color: Colors.blue,
                    ),
                    _buildMiniStat(
                      value: '${_stats['missedToday'] ?? 0}',
                      label: 'Missed',
                      color: Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    String? value,
    Widget? colorWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          if (colorWidget != null) colorWidget,
          if (value != null) Expanded(child: Text(value)),
        ],
        
      ),
    );
  }

  Widget _buildSchedulesTab() {
    return _schedules.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.schedule,
                  size: 80,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Schedules Set',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add a schedule to start tracking this medication',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // Navigate to add schedule page
                  },
                  child: const Text('Add Schedule'),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _schedules.length,
            itemBuilder: (context, index) {
              return _buildScheduleCard(_schedules[index]);
            },
          );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showDatePicker(),
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_formatDate(_selectedHistoryDate)),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<IntakeStatus>(
                value: _selectedStatusFilter,
                hint: const Text('All Status'),
                items: [
                  DropdownMenuItem<IntakeStatus>(
                    value: null,
                    child: Row(
                      children: [
                        Icon(Icons.all_inclusive, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        const Text('All'),
                      ],
                    ),
                  ),
                  ...IntakeStatus.values.map((status) {
                    return DropdownMenuItem<IntakeStatus>(
                      value: status,
                      child: Row(
                        children: [
                          Icon(
                            _getStatusIcon(status),
                            color: _getStatusColor(status),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(status.name.toUpperCase()),
                        ],
                      ),
                    );
                  }).toList(),
                ],
                onChanged: (status) {
                  setState(() {
                    _selectedStatusFilter = status;
                  });
                  _applyFilters();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredIntakeHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 80,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Intake History',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedStatusFilter != null
                            ? 'No ${_selectedStatusFilter!.name} intakes on ${_formatDate(_selectedHistoryDate)}'
                            : 'No intakes on ${_formatDate(_selectedHistoryDate)}',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _filteredIntakeHistory.length,
                  itemBuilder: (context, index) {
                    return _buildIntakeHistoryItem(_filteredIntakeHistory[index]);
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showDatePicker() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedHistoryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (pickedDate != null) {
      setState(() {
        _selectedHistoryDate = pickedDate;
      });
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.medication.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportHistory,
            tooltip: 'Export History',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteMedication,
            tooltip: 'Delete Medication',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadMedicationData();
            },
            tooltip: 'Refresh Data',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.schedule), text: 'Schedules'),
            Tab(icon: Icon(Icons.history), text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildSchedulesTab(),
                      _buildHistoryTab(),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: _schedules.isEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                // Navigate to add schedule page
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Schedule'),
            )
          : null,
    );
  }
}