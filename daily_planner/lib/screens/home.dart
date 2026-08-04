import 'dart:async';
import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/providers/medication_provider.dart';
import 'package:daily_planner/providers/task_provider.dart';
import 'package:daily_planner/screens/add_medication_page.dart';
import 'package:daily_planner/screens/additemPage.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:daily_planner/utils/drawer.dart';
import 'package:daily_planner/utils/item.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum TaskFilter { all, completed, incomplete, overdue }

enum TaskType { oneTime, dailyTask, weeklyTask, monthlyTask }

const taskTypeLabels = {
  'oneTime': 'One-Time Tasks',
  'DailyTask': 'Daily Tasks',
  'WeeklyTask': 'Weekly Tasks',
  'MonthlyTask': 'Monthly Tasks',
};

class MyHome extends StatefulWidget {
  const MyHome({super.key});

  @override
  State<MyHome> createState() => _MyHomeState();
}

class _MyHomeState extends State<MyHome> {
  final TextEditingController _searchController = TextEditingController();
  bool _nativeAlarmInitialized = false;

@override
void initState() {
  super.initState();
  
  // Initialize NativeAlarmHelper first
  _initializeNativeAlarmHelper();
  
  // Check and refresh token, then fetch tasks
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!mounted) return;
    final authProvider = context.read<app_auth.AuthProvider>();
    await authProvider.refreshToken();
    
    if (!mounted) return;
    if (authProvider.user != null) {
      context.read<TaskProvider>().fetchTasks(authProvider.user!);
      context.read<MedicationProvider>().loadMedications(authProvider.user!.uid);
      _maybeRequestAlarmPermission();
    }
  });
  
  _searchController.addListener(() {
    context.read<TaskProvider>().setSearchQuery(_searchController.text);
  });
}

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeNativeAlarmHelper() async {
    try {
      await NativeAlarmHelper.initialize();
      setState(() {
        _nativeAlarmInitialized = true;
      });
      debugPrint('✅ NativeAlarmHelper initialized successfully');
    } catch (e) {
      debugPrint('❌ NativeAlarmHelper initialization failed: $e');
      setState(() {
        _nativeAlarmInitialized = false;
      });
    }
  }

  Future<void> _maybeRequestAlarmPermission() async {
    if (!_nativeAlarmInitialized) {
      debugPrint('NativeAlarmHelper not initialized, skipping permission request');
      return;
    }

    if (!await NativeAlarmHelper.checkExactAlarmPermission()) {
      if (!mounted) return;
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Allow Alarm Permission"),
          content: const Text(
            "We need permission to schedule exact alarms for your tasks and medications.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Yes"),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        // await NativeAlarmHelper.requestExactAlarmPermission();
      }
    }
  }

  Widget buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search tasks by title...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              context.read<TaskProvider>().clearSearch();
            },
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget buildTaskList(TaskFilter filter) {
    final taskProvider = context.watch<TaskProvider>();
    final authProvider = context.watch<app_auth.AuthProvider>();
    final filtered = taskProvider.getFilteredTasks(filter);
    
    if (taskProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (filtered.isEmpty) {
      return Column(
        children: [
          buildSearchBar(),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_alt, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No tasks found",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Try changing filters or add a new task",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    Map<String, List<Task>> groupedTasks = {
      "One-Time Tasks": [],
      "Daily Tasks": [],
      "Weekly Tasks": [],
      "Monthly Tasks": [],
    };

    for (var task in filtered) {
      switch (task.taskType) {
        case "oneTime":
          groupedTasks["One-Time Tasks"]!.add(task);
          break;
        case "DailyTask":
          groupedTasks["Daily Tasks"]!.add(task);
          break;
        case "WeeklyTask":
          groupedTasks["Weekly Tasks"]!.add(task);
          break;
        case "MonthlyTask":
          groupedTasks["Monthly Tasks"]!.add(task);
          break;
        default:
          debugPrint("Unknown task type: ${task.taskType}");
      }
    }

    return Column(
      children: [
        buildSearchBar(),
        if (!_nativeAlarmInitialized)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.orange[800]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Alarm system initializing...',
                    style: TextStyle(
                      color: Colors.orange[800],
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              if (authProvider.user != null) {
                await taskProvider.fetchTasks(authProvider.user!);
              }
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children:
                  groupedTasks.entries
                      .where((entry) => entry.value.isNotEmpty)
                      .map((entry) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: taskProvider
                                          .getFilterColor(filter)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${entry.value.length}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: taskProvider.getFilterColor(filter),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...entry.value.map(
                              (task) => ItemWidget(
                                item: task,
                                onEditDone: () async {
                                  if (authProvider.user != null) {
                                    await taskProvider.fetchTasks(authProvider.user!);
                                  }
                                },
                              ),
                            ),
                          ],
                        );
                      })
                      .toList(),
            ),
          ),
        ),
      ],
    );
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
      MaterialPageRoute(
        builder: (_) => const AddMedicationPage(),
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Add New Item',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.task, color: Colors.blue),
                title: const Text('Add Task'),
                subtitle: const Text('Create a new task or reminder'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToAddTask();
                },
              ),
              ListTile(
                leading: const Icon(Icons.medication, color: Colors.green),
                title: const Text('Add Medication'),
                subtitle: const Text('Schedule medication or vitamins'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToAddMedication();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _testNativeAlarmSystem() async {
    if (!_nativeAlarmInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alarm system not initialized yet'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final testTime = DateTime.now().add(const Duration(seconds: 5));
      
      await NativeAlarmHelper.scheduleAlarmAtTime(
        id: DateTime.now().millisecondsSinceEpoch,
        title: "🔔 Test Alarm",
        body: "This is a test of the native alarm system",
        dateTime: testTime,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Test alarm scheduled for 5 seconds!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to schedule test alarm: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<app_auth.AuthProvider>();
    final user = authProvider.user;
    
    return DefaultTabController(
      length: 4,
      initialIndex: 2, 
      child: Scaffold(
        appBar: AppBar(
          title: const Text("My Tasks"),
          actions: [
            if (_nativeAlarmInitialized)
              IconButton(
                icon: const Icon(Icons.alarm),
                tooltip: 'Test Alarm System',
                onPressed: _testNativeAlarmSystem,
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(
                child: Row(
                  children: [
                    const Text("All"),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  children: [
                    const Text("Completed"),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  children: [
                    const Text("Incomplete"),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  children: [
                    const Text("Overdue"),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        drawer: const MyDrawer(),
        body: authProvider.isLoading
            ? const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Checking authentication..."),
                    ],
                  ),
                ),
              )
            : user == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("🔒 Please login to view your tasks"),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                          child: const Text("Login"),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    children: [
                      buildTaskList(TaskFilter.all),
                      buildTaskList(TaskFilter.completed),
                      buildTaskList(TaskFilter.incomplete),
                      buildTaskList(TaskFilter.overdue),
                    ],
                  ),
        floatingActionButton: user == null
            ? null
            : FloatingActionButton(
                onPressed: _showAddOptions,
                tooltip: 'Add Task or Medication',
                child: const Icon(Icons.add),
              ),
      ),
    );
  }
}