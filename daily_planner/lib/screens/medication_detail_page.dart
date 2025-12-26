import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:flutter/material.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';
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
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  DateTime _selectedHistoryDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMedicationData();
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
      // Load schedules for this medication
      _schedules = widget.medicationManager.schedules
          .where((schedule) =>
              schedule.medication.medicationId ==
              widget.medication.medicationId)
          .toList();

      // Load intake history for this medication
      _intakeHistory = widget.medicationManager.getAllIntakes()
          .where((intake) =>
              intake.schedule.medication.medicationId ==
              widget.medication.medicationId)
          .toList();

      // Sort intake history by date (newest first)
      _intakeHistory.sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));

      // Calculate statistics
      _calculateStats();

      // If user is authenticated, sync with Firebase
      final userId = _getCurrentUserId();
      if (userId != null) {
        await _loadFirebaseData(userId);
      }

    } catch (e) {
      print('Error loading medication details: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFirebaseData(String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // Load additional data from Firebase if needed
      // For example, load adherence rate from Firebase analytics
    } catch (e) {
      print('Error loading Firebase data: $e');
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
    for (final intake in takenIntakes as List<MedicationIntake>) {
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
    };
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
                icon: Icons.check_circle,
                value: '${_stats['taken'] ?? 0}/${_stats['totalScheduled'] ?? 0}',
                label: 'This Month',
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
          ],
        ),
      ),
    );
  }

  String _formatDaysOfWeek(List<int> days) {
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final selectedDays = days.map((day) => dayNames[day]).toList();
    return selectedDays.join(', ');
  }

  Widget _buildIntakeHistoryItem(MedicationIntake intake) {
    return ListTile(
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
        ],
      ),
      trailing: Text(
        _formatDate(intake.scheduledTime),
        style: TextStyle(color: Colors.grey[500]),
      ),
      onTap: () => _showIntakeDetails(intake),
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
        return Colors.grey;
      case IntakeStatus.upcoming:
        return Colors.blue;
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

  void _showIntakeDetails(MedicationIntake intake) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Intake Details'),
        content: Column(
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _editSchedule(MedicationSchedule schedule) {
    // Navigate to edit schedule page
    // You'll need to create an EditSchedulePage
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
      widget.medicationManager.deleteMedication(widget.medication.medicationId!);
      
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
    // Implement export functionality (CSV, PDF, etc.)
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
                    value: _formatDate(_stats['firstIntakeDate']),
                  ),
                if (_stats['mostCommonHour'] != null)
                  _buildDetailItem(
                    icon: Icons.access_time,
                    label: 'Most Common Time',
                    value: '${_stats['mostCommonHour']}:00',
                  ),
              ],
            ),
          ),
        ],
      ),
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
    return _intakeHistory.isEmpty
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
                const Text(
                  'Your intake history will appear here',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _intakeHistory.length,
            itemBuilder: (context, index) {
              return _buildIntakeHistoryItem(_intakeHistory[index]);
            },
          );
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

class _ChartData {
  final String category;
  final int value;
  final Color color;

  _ChartData(this.category, this.value, this.color);
}