import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/medication_provider.dart';
import 'package:daily_planner/screens/add_medication_page.dart';
import 'package:daily_planner/screens/medication_detail_page.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/frequency_and_dosage.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_intake.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daily_planner/services/custom_state_management.dart';

class MedicationListPage extends StatefulWidget {
  const MedicationListPage({super.key});

  @override
  State<MedicationListPage> createState() => _MedicationListPageState();
}

class _MedicationListPageState extends State<MedicationListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ScrollController _dateStripScrollController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _dateStripScrollController = ScrollController();

    // Initial load from Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<app_auth.AuthProvider>();
      if (authProvider.user != null) {
        context
            .read<MedicationProvider>()
            .loadMedications(authProvider.user!.uid);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dateStripScrollController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final medProvider = context.watch<MedicationProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF6F8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Text(
          'Medications',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today_rounded),
            tooltip: 'Go to Today',
            onPressed: () {
              medProvider.selectDate(DateTime.now());
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Medication',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddMedicationPage(),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blueAccent,
          indicatorWeight: 3,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Daily Schedule', icon: Icon(Icons.calendar_today_rounded, size: 20)),
            Tab(text: 'My Medications', icon: Icon(Icons.medication_rounded, size: 20)),
          ],
        ),
      ),
      body: medProvider.isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading medications...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDailyScheduleTab(medProvider, isDark),
                _buildMedicationsListTab(medProvider, isDark),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddMedicationPage()),
          );
        },
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Medication', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // ==========================================
  // TAB 1: DAILY SCHEDULE (APPLE HEALTH STYLE)
  // ==========================================
  Widget _buildDailyScheduleTab(MedicationProvider medProvider, bool isDark) {
    final timeGroups = medProvider.intakesByTimeOfDay;
    final totalDoses = medProvider.totalIntakesCount;

    return RefreshIndicator(
      onRefresh: () async {
        final authProvider = context.read<app_auth.AuthProvider>();
        if (authProvider.user != null) {
          await medProvider.loadMedications(authProvider.user!.uid);
        }
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          // 1. Horizontal 7-Day Date Picker (Apple Health Strip)
          _buildAppleHealthDateStrip(medProvider, isDark),

          const SizedBox(height: 12),

          // 2. Today's Adherence Summary Card
          _buildAdherenceCard(medProvider, isDark),

          const SizedBox(height: 16),

          // 3. Time-of-Day Sections
          if (totalDoses == 0)
            _buildEmptyScheduleCard(medProvider, isDark)
          else ...[
            if (timeGroups['Morning']!.isNotEmpty)
              _buildTimeSection(
                title: 'Morning',
                timeRange: '5:00 AM - 12:00 PM',
                icon: Icons.wb_sunny_outlined,
                iconColor: Colors.amber.shade700,
                intakes: timeGroups['Morning']!,
                medProvider: medProvider,
                isDark: isDark,
              ),
            if (timeGroups['Afternoon']!.isNotEmpty)
              _buildTimeSection(
                title: 'Afternoon',
                timeRange: '12:00 PM - 5:00 PM',
                icon: Icons.wb_cloudy_outlined,
                iconColor: Colors.orange.shade700,
                intakes: timeGroups['Afternoon']!,
                medProvider: medProvider,
                isDark: isDark,
              ),
            if (timeGroups['Evening']!.isNotEmpty)
              _buildTimeSection(
                title: 'Evening',
                timeRange: '5:00 PM - 9:00 PM',
                icon: Icons.nights_stay_outlined,
                iconColor: Colors.indigo.shade400,
                intakes: timeGroups['Evening']!,
                medProvider: medProvider,
                isDark: isDark,
              ),
            if (timeGroups['Night']!.isNotEmpty)
              _buildTimeSection(
                title: 'Night',
                timeRange: '9:00 PM - 5:00 AM',
                icon: Icons.bedtime_outlined,
                iconColor: Colors.purple.shade400,
                intakes: timeGroups['Night']!,
                medProvider: medProvider,
                isDark: isDark,
              ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // Apple Health Style Horizontal Date Strip (14 days)
  // ----------------------------------------------------
  Widget _buildAppleHealthDateStrip(MedicationProvider medProvider, bool isDark) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Generate dates: 6 days before today to 7 days after
    final dates = List.generate(
      14,
      (i) => today.subtract(const Duration(days: 6)).add(Duration(days: i)),
    );

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(medProvider.selectedDate),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  DateFormat('EEEE, MMM d').format(medProvider.selectedDate),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 76,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: dates.length,
              itemBuilder: (context, index) {
                final date = dates[index];
                final isSelected = date.year == medProvider.selectedDate.year &&
                    date.month == medProvider.selectedDate.month &&
                    date.day == medProvider.selectedDate.day;
                final isCurrentToday = date.year == today.year &&
                    date.month == today.month &&
                    date.day == today.day;

                return GestureDetector(
                  onTap: () {
                    medProvider.selectDate(date);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blueAccent
                          : (isCurrentToday
                              ? (isDark
                                  ? Colors.blueAccent.withValues(alpha: 0.2)
                                  : Colors.blue.shade50)
                              : (isDark
                                  ? const Color(0xFF2A2A2A)
                                  : Colors.grey.shade100)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? Colors.blueAccent
                            : (isCurrentToday
                                ? Colors.blueAccent.withValues(alpha: 0.5)
                                : Colors.transparent),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(date).toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        if (isCurrentToday)
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : Colors.blueAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // Adherence Card (Circular Progress & Counters)
  // ----------------------------------------------------
  Widget _buildAdherenceCard(MedicationProvider medProvider, bool isDark) {
    final pct = medProvider.adherencePercentage;
    final total = medProvider.totalIntakesCount;
    final taken = medProvider.takenIntakesCount;
    final skipped = medProvider.skippedIntakesCount;
    final pending = medProvider.pendingIntakesCount;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [Colors.blue.shade700, Colors.indigo.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Progress
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: total == 0 ? 0.0 : pct,
                  strokeWidth: 7,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                ),
                Center(
                  child: Text(
                    total == 0 ? '0%' : '${(pct * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          // Info & Badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    total == 0
                        ? 'No Medications Scheduled'
                        : (pct >= 1.0
                            ? '🎉 All Medications Taken!'
                            : '$taken of $total doses completed'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildStatPill('Taken: $taken', Colors.greenAccent.shade400, Colors.green.shade900),
                    _buildStatPill('Pending: $pending', Colors.blue.shade100, Colors.blue.shade900),
                    if (skipped > 0)
                      _buildStatPill('Skipped: $skipped', Colors.amber.shade200, Colors.brown.shade800),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          maxLines: 1,
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // Time-of-Day Group Section
  // ----------------------------------------------------
  Widget _buildTimeSection({
    required String title,
    required String timeRange,
    required IconData icon,
    required Color iconColor,
    required List<MedicationIntake> intakes,
    required MedicationProvider medProvider,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• $timeRange',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        ...intakes.map(
          (intake) => _buildAppleHealthIntakeCard(intake, medProvider, isDark),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ----------------------------------------------------
  // Apple Health Style Intake Card with Quick Actions
  // ----------------------------------------------------
  Widget _buildAppleHealthIntakeCard(
    MedicationIntake intake,
    MedicationProvider medProvider,
    bool isDark,
  ) {
    final med = intake.schedule.medication;
    final medColor = _parseColor(med.color);
    final timeStr = DateFormat('h:mm a').format(intake.scheduledTime);
    final isTaken = intake.status == IntakeStatus.taken;
    final isSkipped = intake.status == IntakeStatus.skipped;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTaken
              ? Colors.green.withValues(alpha: 0.3)
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MedicationDetailPage(medication: med),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              // Medication Icon Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: medColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    med.icon,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Title, Dosage, Instructions
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            med.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              decoration: isSkipped
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${med.dosage} ${med.unit.name}${intake.schedule.instructions != null && intake.schedule.instructions!.isNotEmpty ? ' • ${intake.schedule.instructions}' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    if (isTaken && intake.actualTime != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.check_circle, size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Taken at ${DateFormat('h:mm a').format(intake.actualTime!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // Action Buttons: Taken / Skipped / Toggle
              if (isTaken)
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                  tooltip: 'Mark as Pending',
                  onPressed: () {
                    medProvider.markIntake(
                      intake: intake,
                      status: IntakeStatus.pending,
                    );
                  },
                )
              else if (isSkipped)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.orange, size: 28),
                  tooltip: 'Mark as Pending',
                  onPressed: () {
                    medProvider.markIntake(
                      intake: intake,
                      status: IntakeStatus.pending,
                    );
                  },
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Skip Button
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 22),
                      tooltip: 'Skip dose',
                      onPressed: () {
                        medProvider.markIntake(
                          intake: intake,
                          status: IntakeStatus.skipped,
                        );
                      },
                    ),
                    // Take Button (Apple Health Pill)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        medProvider.markIntake(
                          intake: intake,
                          status: IntakeStatus.taken,
                          actualTime: DateTime.now(),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 16),
                          SizedBox(width: 4),
                          Text('Take', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyScheduleCard(MedicationProvider medProvider, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded, size: 64, color: Colors.blueAccent.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'No Intakes Scheduled',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'You have no medications scheduled for ${DateFormat('MMMM d, yyyy').format(medProvider.selectedDate)}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddMedicationPage()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Medication Schedule'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: MY MEDICATIONS LIST
  // ==========================================
  Widget _buildMedicationsListTab(MedicationProvider medProvider, bool isDark) {
    final medications = medProvider.medications;

    if (medications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.medication_outlined, size: 70, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No Medications Added Yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add your prescriptions, vitamins, and supplements to manage intake schedules and adherence.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddMedicationPage()),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Your First Medication'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: medications.length,
      itemBuilder: (context, index) {
        final med = medications[index];
        final medColor = _parseColor(med.color);

        // Find schedules for this med
        final schedules = medProvider.schedules
            .where((s) => s.medication.medicationId == med.medicationId)
            .toList();

        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: medColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(med.icon, style: const TextStyle(fontSize: 22)),
              ),
            ),
            title: Text(
              med.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('${med.dosage} ${med.unit.name}'),
                if (schedules.isNotEmpty)
                  Text(
                    '${schedules.first.frequency.name.toUpperCase()} • ${schedules.first.timesPerDay.length}x daily',
                    style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  final schedule = schedules.isNotEmpty ? schedules.first : null;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddMedicationPage(
                        existingMedication: med,
                        existingSchedule: schedule,
                      ),
                    ),
                  );
                } else if (value == 'delete') {
                  _showDeleteConfirmDialog(med, medProvider);
                }
              },
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MedicationDetailPage(medication: med),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showDeleteConfirmDialog(Medication med, MedicationProvider medProvider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${med.name}?'),
        content: const Text(
          'This will permanently delete this medication, its schedules, and all recorded intake logs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await medProvider.deleteMedication(med.medicationId);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${med.name} deleted')),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
