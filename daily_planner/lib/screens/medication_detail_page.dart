import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/medication_provider.dart';
import 'package:daily_planner/screens/add_medication_page.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_schedule_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daily_planner/services/custom_state_management.dart';

class MedicationDetailPage extends StatefulWidget {
  final Medication medication;

  const MedicationDetailPage({
    super.key,
    required this.medication,
  });

  @override
  State<MedicationDetailPage> createState() => _MedicationDetailPageState();
}

class _MedicationDetailPageState extends State<MedicationDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<MedicationIntake> _history = [];
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadIntakeHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _parseColor(String colorHex) {
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

  Future<void> _loadIntakeHistory() async {
    setState(() {
      _isLoadingHistory = true;
    });

    final authProvider = context.read<app_auth.AuthProvider>();
    final medProvider = context.read<MedicationProvider>();
    final userId = authProvider.user?.uid;

    if (userId == null) {
      setState(() {
        _isLoadingHistory = false;
      });
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('medications')
          .doc(widget.medication.medicationId)
          .collection('intakes')
          .orderBy('scheduledTime', descending: true)
          .limit(50)
          .get();

      final List<MedicationIntake> list = [];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final scheduleId = data['scheduleId'];
          MedicationSchedule? sched;
          try {
            sched = medProvider.schedules
                .firstWhere((s) => s.scheduleId == scheduleId);
          } catch (_) {
            sched = null;
          }
          list.add(MedicationIntake.fromMap(data, doc.id, sched));
        } catch (e) {
          debugPrint('Error parsing history intake: $e');
        }
      }

      setState(() {
        _history = list;
      });
    } catch (e) {
      debugPrint('Error loading intake history: $e');
    } finally {
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final medProvider = context.watch<MedicationProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final medColor = _parseColor(widget.medication.color);

    // Find schedule for this medication
    final schedule = medProvider.schedules.cast<MedicationSchedule?>().firstWhere(
          (s) => s?.medication.medicationId == widget.medication.medicationId,
          orElse: () => null,
        );

    final takenCount = _history.where((i) => i.status == IntakeStatus.taken).length;
    final skippedCount = _history.where((i) => i.status == IntakeStatus.skipped).length;
    final totalLogged = _history.length;
    final adherenceRate = totalLogged > 0 ? (takenCount / totalLogged) : 1.0;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: Text(widget.medication.name),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit Medication',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddMedicationPage(
                    existingMedication: widget.medication,
                    existingSchedule: schedule,
                  ),
                ),
              );
              _loadIntakeHistory();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(medProvider),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: medColor,
          labelColor: medColor,
          unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined, size: 20)),
            Tab(text: 'History', icon: Icon(Icons.history_rounded, size: 20)),
            Tab(text: 'Schedule', icon: Icon(Icons.alarm_on_rounded, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Overview
          _buildOverviewTab(medColor, isDark, adherenceRate, takenCount, skippedCount, totalLogged, schedule),
          // Tab 2: History
          _buildHistoryTab(isDark, medProvider),
          // Tab 3: Schedule Details
          _buildScheduleTab(schedule, isDark),
        ],
      ),
    );
  }

  // ---------------------------------------------
  // TAB 1: OVERVIEW
  // ---------------------------------------------
  Widget _buildOverviewTab(
    Color medColor,
    bool isDark,
    double adherenceRate,
    int takenCount,
    int skippedCount,
    int totalLogged,
    MedicationSchedule? schedule,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Medication Hero Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: medColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
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
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.medication.dosage} ${widget.medication.unit.name}',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.medication.description != null &&
                        widget.medication.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.medication.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Adherence Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adherence Summary',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: totalLogged == 0 ? 1.0 : adherenceRate,
                          strokeWidth: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(medColor),
                        ),
                        Center(
                          child: Text(
                            totalLogged == 0
                                ? '100%'
                                : '${(adherenceRate * 100).toInt()}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatRow('Total Logged', '$totalLogged doses'),
                        const SizedBox(height: 6),
                        _buildStatRow('Taken On-Time', '$takenCount', Colors.green),
                        const SizedBox(height: 6),
                        _buildStatRow('Skipped', '$skippedCount', Colors.orange),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Quick Instructions & Notes Card
        if (schedule?.instructions != null && schedule!.instructions!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withValues(alpha: isDark ? 0.1 : 0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.blueAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    schedule.instructions!,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, [Color? valueColor]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------
  // TAB 2: HISTORY
  // ---------------------------------------------
  Widget _buildHistoryTab(bool isDark, MedicationProvider medProvider) {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No Intake Logs Yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Mark your medication as taken on the daily schedule.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final intake = _history[index];
        final isTaken = intake.status == IntakeStatus.taken;
        final isSkipped = intake.status == IntakeStatus.skipped;

        Color badgeBg = Colors.grey.shade200;
        Color badgeColor = Colors.grey.shade800;
        String statusLabel = 'Pending';

        if (isTaken) {
          badgeBg = Colors.green.shade50;
          badgeColor = Colors.green.shade700;
          statusLabel = 'Taken';
        } else if (isSkipped) {
          badgeBg = Colors.orange.shade50;
          badgeColor = Colors.orange.shade800;
          statusLabel = 'Skipped';
        } else if (intake.status == IntakeStatus.missed) {
          badgeBg = Colors.red.shade50;
          badgeColor = Colors.red.shade700;
          statusLabel = 'Missed';
        }

        return Card(
          elevation: 0.5,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            onTap: () => _showModifyIntakeBottomSheet(context, intake),
            leading: Icon(
              isTaken
                  ? Icons.check_circle_rounded
                  : (isSkipped ? Icons.remove_circle_outline : Icons.schedule_rounded),
              color: badgeColor,
            ),
            title: Text(
              DateFormat('EEEE, MMM d, yyyy').format(intake.logicalDate),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              'Scheduled: ${DateFormat('h:mm a').format(intake.scheduledTime)}${intake.actualTime != null ? ' • Logged: ${DateFormat('h:mm a').format(intake.actualTime!)}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: badgeColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showModifyIntakeBottomSheet(BuildContext context, MedicationIntake intake) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Modify Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (intake.status != IntakeStatus.taken)
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text('Mark as Taken'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final TimeOfDay? pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(intake.scheduledTime),
                      helpText: 'Select time taken',
                    );
                    
                    if (pickedTime != null) {
                      final actualTime = DateTime(
                        intake.scheduledTime.year,
                        intake.scheduledTime.month,
                        intake.scheduledTime.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                      if (context.mounted) {
                        await context.read<MedicationProvider>().markIntake(
                          intake: intake, 
                          status: IntakeStatus.taken,
                          actualTime: actualTime,
                        );
                        _loadIntakeHistory();
                      }
                    }
                  },
                ),
              if (intake.status != IntakeStatus.skipped)
                ListTile(
                  leading: const Icon(Icons.remove_circle, color: Colors.orange),
                  title: const Text('Mark as Skipped'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await context.read<MedicationProvider>().markIntake(intake: intake, status: IntakeStatus.skipped);
                    _loadIntakeHistory();
                  },
                ),
              if (intake.status != IntakeStatus.missed)
                ListTile(
                  leading: const Icon(Icons.cancel, color: Colors.red),
                  title: const Text('Mark as Missed'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await context.read<MedicationProvider>().markIntake(intake: intake, status: IntakeStatus.missed);
                    _loadIntakeHistory();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.pending_actions, color: Colors.grey),
                title: const Text('Reset to Pending'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await context.read<MedicationProvider>().markIntake(intake: intake, status: IntakeStatus.pending);
                  _loadIntakeHistory();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------
  // TAB 3: SCHEDULE
  // ---------------------------------------------
  Widget _buildScheduleTab(MedicationSchedule? schedule, bool isDark) {
    if (schedule == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.alarm_off_rounded, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No Active Schedule',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddMedicationPage(
                      existingMedication: widget.medication,
                    ),
                  ),
                );
              },
              child: const Text('Add Schedule'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Schedule Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 24),
                _buildScheduleDetailRow(
                  'Frequency',
                  schedule.frequency.name.toUpperCase(),
                ),
                const SizedBox(height: 12),
                _buildScheduleDetailRow(
                  'Doses Per Day',
                  '${schedule.timesPerDay.length} time(s)',
                ),
                const SizedBox(height: 12),
                _buildScheduleDetailRow(
                  'Times',
                  schedule.timesPerDay
                      .map((t) => DateFormat('h:mm a').format(
                            DateTime(2022, 1, 1, t.hour, t.minute),
                          ))
                      .join(', '),
                ),
                const SizedBox(height: 12),
                _buildScheduleDetailRow(
                  'Start Date',
                  DateFormat('MMM d, yyyy').format(schedule.startDate),
                ),
                if (schedule.endDate != null) ...[
                  const SizedBox(height: 12),
                  _buildScheduleDetailRow(
                    'End Date',
                    DateFormat('MMM d, yyyy').format(schedule.endDate!),
                  ),
                ],
                const SizedBox(height: 12),
                _buildScheduleDetailRow(
                  'Reminder Alert',
                  '${schedule.reminderMinutesBefore} mins before',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  void _confirmDelete(MedicationProvider medProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.medication.name}?'),
        content: const Text(
          'This will permanently delete this medication, its schedules, and all recorded intakes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Close detail page
              await medProvider.deleteMedication(widget.medication.medicationId);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}