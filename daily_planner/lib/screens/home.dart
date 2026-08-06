import 'dart:async';
import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/medication_provider.dart';
import 'package:daily_planner/providers/task_provider.dart';
import 'package:daily_planner/screens/add_medication_page.dart';
import 'package:daily_planner/screens/additemPage.dart';
import 'package:daily_planner/screens/medication_list_page.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:daily_planner/utils/drawer.dart';
import 'package:daily_planner/utils/item.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daily_planner/services/custom_state_management.dart';

enum TaskFilter { all, completed, incomplete, overdue }

class MyHome extends StatefulWidget {
  const MyHome({super.key});

  @override
  State<MyHome> createState() => _MyHomeState();
}

class _MyHomeState extends State<MyHome> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  Timer? _debounceTimer;
  bool _nativeAlarmInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 0);

    _initializeNativeAlarmHelper();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final authProvider = context.read<app_auth.AuthProvider>();
      await authProvider.refreshToken();

      if (!mounted) return;
      if (authProvider.user != null) {
        context.read<TaskProvider>().fetchTasks(authProvider.user!);
        context.read<MedicationProvider>().loadMedications(authProvider.user!.uid);
      }
    });

    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        context.read<TaskProvider>().setSearchQuery(_searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initializeNativeAlarmHelper() async {
    try {
      await NativeAlarmHelper.initialize();
      if (mounted) {
        setState(() {
          _nativeAlarmInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('NativeAlarmHelper initialization note: $e');
    }
  }

  Future<void> _navigateToAddTask() async {
    final authProvider = context.read<app_auth.AuthProvider>();
    final taskProvider = context.read<TaskProvider>();

    final added = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddTaskPage()),
    );
    if (added == true && authProvider.user != null) {
      await taskProvider.fetchTasks(authProvider.user!);
    }
  }

  Future<void> _navigateToAddMedication() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMedicationPage()),
    );
  }

  void _showAddOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Quick Create',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: Color(0xFF2563EB)),
                  ),
                  title: const Text('Add Task', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Schedule one-time or recurring reminders'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateToAddTask();
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.medication_outlined, color: Color(0xFF10B981)),
                  ),
                  title: const Text('Add Medication', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Log doses, frequencies and inventory'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateToAddMedication();
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // Modern Hero Progress & Summary Banner
  Widget _buildSummaryHeroCard(TaskProvider taskProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = taskProvider.totalTasksCount;
    final completed = taskProvider.completedTasksCount;
    final incomplete = taskProvider.incompleteTasksCount;
    final overdue = taskProvider.overdueTasksCount;
    final progress = taskProvider.completionRate;
    final formattedDate = DateFormat('EEEE, MMMM d').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFF2563EB), const Color(0xFF1D4ED8)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formattedDate,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Today's Overview",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Circular Percentage Badge
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      value: total == 0 ? 0.0 : progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 4,
                    ),
                  ),
                  Text(
                    total == 0 ? "0%" : "${(progress * 100).toInt()}%",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Statistics Pills Row
          Row(
            children: [
              _buildStatChip("Done", completed, const Color(0xFF10B981), Icons.check_circle),
              const SizedBox(width: 8),
              _buildStatChip("Pending", incomplete, const Color(0xFFF59E0B), Icons.schedule),
              const SizedBox(width: 8),
              _buildStatChip("Overdue", overdue, const Color(0xFFEF4444), Icons.error_outline),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  "$count $label",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search tasks by title or details...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    context.read<TaskProvider>().clearSearch();
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildTabBar(TaskProvider taskProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        indicator: BoxDecoration(
          color: isDark ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
        unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        tabs: [
          Tab(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text("All (${taskProvider.getTaskCount(TaskFilter.all)})"),
            ),
          ),
          Tab(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text("Done (${taskProvider.getTaskCount(TaskFilter.completed)})"),
            ),
          ),
          Tab(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text("Pending (${taskProvider.getTaskCount(TaskFilter.incomplete)})"),
            ),
          ),
          Tab(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text("Overdue (${taskProvider.getTaskCount(TaskFilter.overdue)})"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(TaskFilter filter, bool isSearching) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String title;
    String subtitle;
    IconData icon;
    Color iconColor;

    if (isSearching) {
      title = "No tasks found";
      subtitle = "No tasks match your search query.";
      icon = Icons.search_off_rounded;
      iconColor = Colors.grey;
    } else {
      switch (filter) {
        case TaskFilter.completed:
          title = "No completed tasks yet";
          subtitle = "Check off tasks as you finish them!";
          icon = Icons.check_circle_outline_rounded;
          iconColor = const Color(0xFF10B981);
          break;
        case TaskFilter.incomplete:
          title = "All caught up!";
          subtitle = "You have no pending tasks right now.";
          icon = Icons.done_all_rounded;
          iconColor = const Color(0xFF2563EB);
          break;
        case TaskFilter.overdue:
          title = "Zero overdue tasks!";
          subtitle = "Awesome job staying on schedule.";
          icon = Icons.celebration_outlined;
          iconColor = const Color(0xFF10B981);
          break;
        case TaskFilter.all:
          title = "No tasks created yet";
          subtitle = "Tap below to add your first task.";
          icon = Icons.add_task_rounded;
          iconColor = const Color(0xFF2563EB);
          break;
      }
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: iconColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (!isSearching && filter == TaskFilter.all)
              FilledButton.icon(
                onPressed: _navigateToAddTask,
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Create Task"),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedTaskList(TaskFilter filter) {
    final taskProvider = context.watch<TaskProvider>();
    final authProvider = context.watch<app_auth.AuthProvider>();
    final filtered = taskProvider.getFilteredTasks(filter);
    final isSearching = taskProvider.searchQuery.isNotEmpty;

    if (taskProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (filtered.isEmpty) {
      return _buildEmptyState(filter, isSearching);
    }

    // Grouping tasks efficiently
    final List<Task> oneTimeTasks = [];
    final List<Task> dailyTasks = [];
    final List<Task> weeklyTasks = [];
    final List<Task> monthlyTasks = [];

    for (var task in filtered) {
      final type = task.taskType.toLowerCase();
      if (type == 'dailytask') {
        dailyTasks.add(task);
      } else if (type == 'weeklytask') {
        weeklyTasks.add(task);
      } else if (type == 'monthlytask') {
        monthlyTasks.add(task);
      } else {
        oneTimeTasks.add(task);
      }
    }

    final groups = [
      if (dailyTasks.isNotEmpty) ('Daily Tasks', dailyTasks, const Color(0xFF3B82F6)),
      if (oneTimeTasks.isNotEmpty) ('One-Time Tasks', oneTimeTasks, const Color(0xFF64748B)),
      if (weeklyTasks.isNotEmpty) ('Weekly Tasks', weeklyTasks, const Color(0xFF10B981)),
      if (monthlyTasks.isNotEmpty) ('Monthly Tasks', monthlyTasks, const Color(0xFF8B5CF6)),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        if (authProvider.user != null) {
          await taskProvider.fetchTasks(authProvider.user!);
        }
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96, top: 4),
        itemCount: groups.fold<int>(0, (sum, g) => sum + 1 + g.$2.length),
        itemBuilder: (context, index) {
          int count = 0;
          for (var group in groups) {
            final title = group.$1;
            final taskList = group.$2;
            final color = group.$3;

            // Header position
            if (index == count) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${taskList.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            count++;
            // Items in group
            if (index < count + taskList.length) {
              final task = taskList[index - count];
              return ItemWidget(
                item: task,
                searchQuery: taskProvider.searchQuery,
                onEditDone: () async {
                  if (authProvider.user != null) {
                    await taskProvider.fetchTasks(authProvider.user!);
                  }
                },
              );
            }

            count += taskList.length;
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<app_auth.AuthProvider>();
    final taskProvider = context.watch<TaskProvider>();
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Daily Planner"),
        actions: [
          IconButton(
            icon: const Icon(Icons.medication_outlined),
            tooltip: 'Medications',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MedicationListPage()),
              );
            },
          ),
          if (_nativeAlarmInitialized)
            IconButton(
              icon: const Icon(Icons.alarm_on_outlined),
              tooltip: 'Background Setup Guide',
              onPressed: () => NativeAlarmHelper.showOemOptimizationGuide(context),
            ),
        ],
      ),
      drawer: const MyDrawer(),
      body: authProvider.isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Loading tasks..."),
                ],
              ),
            )
          : user == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 54, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text("Please log in to manage your daily tasks"),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          Navigator.pushReplacementNamed(context, '/login');
                        },
                        child: const Text("Go to Login"),
                      ),
                    ],
                  ),
                )
              : NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _buildSummaryHeroCard(taskProvider),
                          _buildSearchBar(),
                          _buildTabBar(taskProvider),
                        ],
                      ),
                    ),
                  ],
                  body: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildGroupedTaskList(TaskFilter.all),
                      _buildGroupedTaskList(TaskFilter.completed),
                      _buildGroupedTaskList(TaskFilter.incomplete),
                      _buildGroupedTaskList(TaskFilter.overdue),
                    ],
                  ),
                ),
      floatingActionButton: user == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddOptions,
              icon: const Icon(Icons.add),
              label: const Text("Add"),
            ),
    );
  }
}