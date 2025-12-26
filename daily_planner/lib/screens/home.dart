import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/add_medication_page.dart';
import 'package:daily_planner/screens/additemPage.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/Medicaltion%20Model/medication_manager_service.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:daily_planner/utils/drawer.dart';
import 'package:daily_planner/utils/item.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum TaskFilter { all, completed, incomplete, overdue }

enum TaskType { oneTime, dailyTask, weeklyTask, monthlyTask }

const taskTypeLabels = {
  'oneTime': 'One-Time Tasks',
  'DailyTask': 'Daily Tasks',
  'WeeklyTask': 'Weekly Tasks',
  'MonthlyTask': 'Monthly Tasks',
};

final MedicationManager medicationManager = MedicationManager();

class MyHome extends StatefulWidget {
  const MyHome({super.key, });

  @override
  State<MyHome> createState() => _MyHomeState();
}

class _MyHomeState extends State<MyHome> {
  List<Task> tasks = [];
  List<Task> displayTasks = []; // Tasks after applying completion status checks
  bool isLoading = true;
  User? user;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = "";
  bool _nativeAlarmInitialized = false;
  bool _authChecking = true;
  StreamSubscription<User?>? _authSubscription;

  // Add Medication Manager
  final MedicationManager _medicationManager = MedicationManager();

@override
void initState() {
  super.initState();
  
  // Initialize NativeAlarmHelper first
  _initializeNativeAlarmHelper();
  
  // Check and refresh token first
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _checkAndRefreshToken();
  });
  
  // Then check for existing user
  _checkExistingUser();
  
  _searchController.addListener(() {
    setState(() {
      searchQuery = _searchController.text.trim().toLowerCase();
    });
  });
}

  @override
  void dispose() {
    _authSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Helper to get start of week (Monday)
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    final daysFromMonday = (weekday + 6) % 7;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  // ✅ FIXED: Check and update ALL tasks' completion status when fetched
  Future<List<Task>> _updateTasksCompletionStatus(List<Task> fetchedTasks) async {
    if (user == null) return fetchedTasks;

    final List<Task> updatedTasks = [];
    final List<Task> tasksToReset = [];

    for (var task in fetchedTasks) {
      // Create a copy of the task
      Task updatedTask = Task(
        docId: task.docId,
        title: task.title,
        detail: task.detail,
        date: task.date,
        createdAt: task.createdAt,
        isCompleted: task.isCompleted,
        completedAt: task.completedAt,
        taskType: task.taskType,
        // Copy any other properties your Task class has
      );

      // For one-time tasks, just use the stored status
      if (task.taskType == 'oneTime') {
        updatedTasks.add(updatedTask);
        continue;
      }

      // For recurring tasks that are marked as completed
      if (task.isCompleted && task.completedAt != null) {
        final now = DateTime.now();
        final completedDate = task.completedAt!;
        bool needsReset = false;

        switch (task.taskType) {
          case 'DailyTask':
            final today = DateTime(now.year, now.month, now.day);
            final completedDay = DateTime(
              completedDate.year,
              completedDate.month,
              completedDate.day,
            );
            needsReset = completedDay.isBefore(today);
            break;

          case 'WeeklyTask':
            final currentWeekStart = _getWeekStart(now);
            final completedWeekStart = _getWeekStart(completedDate);
            needsReset = completedWeekStart.isBefore(currentWeekStart);
            break;

          case 'MonthlyTask':
            final currentMonth = DateTime(now.year, now.month);
            final completedMonth = DateTime(completedDate.year, completedDate.month);
            needsReset = completedMonth.isBefore(currentMonth);
            break;
        }

        if (needsReset) {
          // Mark task as incomplete for display
          updatedTask = updatedTask.copyWith(
            isCompleted: false,
            completedAt: null,
          );
          
          // Add to list to update in Firestore
          tasksToReset.add(task);
        }
      }

      updatedTasks.add(updatedTask);
    }

    // Update Firestore for tasks that need reset
    if (tasksToReset.isNotEmpty) {
      await _resetTasksInFirestore(tasksToReset);
    }

    return updatedTasks;
  }

  // ✅ FIXED: Reset tasks in Firestore
  Future<void> _resetTasksInFirestore(List<Task> tasksToReset) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      
      for (var task in tasksToReset) {
        final taskRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .collection('tasks')
            .doc(task.docId);
        
        batch.update(taskRef, {
          'isCompleted': false,
          'completedAt': null,
          'lastResetAt': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      debugPrint("✅ Auto-reset ${tasksToReset.length} recurring tasks");
    } catch (e) {
      debugPrint("❌ Error auto-resetting tasks: $e");
    }
  }

  // ✅ FIXED: Get effective completion status for display (synchronous)
  bool _getEffectiveCompletionStatus(Task task) {
    // For one-time tasks, just return the stored status
    if (task.taskType == 'oneTime') {
      return task.isCompleted;
    }
    
    // For recurring tasks that aren't completed, return false
    if (!task.isCompleted) {
      return false;
    }
    
    // If completedAt is null, treat as not completed
    if (task.completedAt == null) {
      return false;
    }
    
    final now = DateTime.now();
    final completedDate = task.completedAt!;
    
    switch (task.taskType) {
      case 'DailyTask':
        final today = DateTime(now.year, now.month, now.day);
        final completedDay = DateTime(
          completedDate.year,
          completedDate.month,
          completedDate.day,
        );
        return completedDay.isAtSameMomentAs(today);
        
      case 'WeeklyTask':
        final currentWeekStart = _getWeekStart(now);
        final completedWeekStart = _getWeekStart(completedDate);
        return completedWeekStart.isAtSameMomentAs(currentWeekStart);
        
      case 'MonthlyTask':
        final currentMonth = DateTime(now.year, now.month);
        final completedMonth = DateTime(completedDate.year, completedDate.month);
        return completedMonth.isAtSameMomentAs(currentMonth);
        
      default:
        return task.isCompleted;
    }
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

  // Future<void> _checkExistingUser() async {
  //   try {
  //     final currentUser = FirebaseAuth.instance.currentUser;
      
  //     if (currentUser != null) {
  //       debugPrint('✅ User found in cache: ${currentUser.email}');
        
  //       setState(() {
  //         user = currentUser;
  //         _authChecking = false;
  //       });
        
  //       await fetchTasksFromFirestore(currentUser);
  //       _maybeRequestAlarmPermission();
  //     } else {
  //       debugPrint('⚠️ No cached user found, listening for auth changes');
  //       setState(() {
  //         _authChecking = false;
  //       });
  //     }
      
  //     _authSubscription = FirebaseAuth.instance.authStateChanges().listen((newUser) async {
  //       if (mounted) {
  //         setState(() {
  //           user = newUser;
  //         });
          
  //         if (newUser != null) {
  //           debugPrint('🔄 User logged in/updated: ${newUser.email}');
  //           await fetchTasksFromFirestore(newUser);
  //           _maybeRequestAlarmPermission();
  //         } else {
  //           debugPrint('🔴 User logged out');
  //           setState(() {
  //             tasks.clear();
  //             displayTasks.clear();
  //           });
  //         }
  //       }
  //     });
      
  //   } catch (e) {
  //     debugPrint('❌ Error checking existing user: $e');
  //     setState(() {
  //       _authChecking = false;
  //     });
  //   }
  // }

  Future<void> _checkExistingUser() async {
  try {
    debugPrint('🔍 Checking for cached user...');
    
    // Wait for Firebase Auth to initialize completely
    await Future.delayed(const Duration(milliseconds: 500));
    
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser != null) {
      debugPrint('✅ User found in cache: ${currentUser.uid}');
      debugPrint('📧 Email: ${currentUser.email}');
      debugPrint('🕒 Last sign-in: ${currentUser.metadata.lastSignInTime}');
      
      if (mounted) {
        setState(() {
          user = currentUser;
          _authChecking = false;
        });
        
        // Fetch tasks immediately
        await fetchTasksFromFirestore(currentUser);
        _maybeRequestAlarmPermission();
      }
    } else {
      debugPrint('⚠️ No cached user found');
      if (mounted) {
        setState(() {
          _authChecking = false;
        });
      }
    }
    
    // Set up auth state listener
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((newUser) async {
      debugPrint('🔄 Auth state changed: ${newUser != null ? "User logged in" : "User logged out"}');
      
      if (mounted) {
        setState(() {
          user = newUser;
        });
        
        if (newUser != null) {
          debugPrint('👤 New user detected: ${newUser.email}');
          await fetchTasksFromFirestore(newUser);
          _maybeRequestAlarmPermission();
        } else {
          debugPrint('🔴 User logged out');
          setState(() {
            tasks.clear();
            displayTasks.clear();
          });
          
          // Optionally navigate to login page
          // WidgetsBinding.instance.addPostFrameCallback((_) {
          //   Navigator.pushReplacementNamed(context, '/login');
          // });
        }
      }
    });
    
  } catch (e) {
    debugPrint('❌ Error checking existing user: $e');
    if (mounted) {
      setState(() {
        _authChecking = false;
      });
    }
  }
}

Future<void> _checkAndRefreshToken() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Get the ID token, this will refresh it if expired
      await user.getIdToken(true);
      debugPrint('✅ Token refreshed for user: ${user.email}');
    }
  } catch (e) {
    debugPrint('❌ Token refresh error: $e');
  }
}

  Future<void> _maybeRequestAlarmPermission() async {
    if (!_nativeAlarmInitialized) {
      debugPrint('NativeAlarmHelper not initialized, skipping permission request');
      return;
    }

    if (!await NativeAlarmHelper.checkExactAlarmPermission()) {
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

  Future<void> fetchTasksFromFirestore(User user) async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    List<Task> allTasks = [];

    try {
      // Try cache first
      final cachedSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .orderBy('createdAt', descending: true)
          .get(const GetOptions(source: Source.cache));

      allTasks =
          cachedSnapshot.docs
              .map((doc) => Task.fromMap(doc.data(), docId: doc.id))
              .toList();
              
      debugPrint("✅ Loaded ${allTasks.length} tasks from cache");
      
      // Update completion status and get display tasks
      final updatedTasks = await _updateTasksCompletionStatus(allTasks);
      
      if (mounted) {
        setState(() {
          tasks = allTasks;
          displayTasks = updatedTasks;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading cached tasks: $e");
    }

    try {
      // Then try server
      final serverSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .orderBy('createdAt', descending: true)
          .get(const GetOptions(source: Source.server));

      final serverTasks =
          serverSnapshot.docs
              .map((doc) => Task.fromMap(doc.data(), docId: doc.id))
              .toList();

      debugPrint("✅ Loaded ${serverTasks.length} tasks from server");

      // Update completion status and get display tasks
      final updatedTasks = await _updateTasksCompletionStatus(serverTasks);
      
      if (mounted) {
        setState(() {
          tasks = serverTasks;
          displayTasks = updatedTasks;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Server fetch failed (offline?): $e");
      
      if (mounted && isLoading) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  bool _isTaskOverdue(Task task) {
    // Use displayTasks for accurate completion status
    final taskToCheck = displayTasks.firstWhere(
      (t) => t.docId == task.docId,
      orElse: () => task,
    );
    
    if (_getEffectiveCompletionStatus(taskToCheck)) return false;
    
    if (task.date == null) return false;
    
    final now = DateTime.now();
    return task.date!.isBefore(now);
  }

  List<Task> getFilteredTasks(TaskFilter filter) {
    return displayTasks.where((task) {
      final effectiveCompleted = _getEffectiveCompletionStatus(task);
      
      final matchesFilter = switch (filter) {
        TaskFilter.completed => effectiveCompleted,
        TaskFilter.incomplete => !effectiveCompleted && !_isTaskOverdue(task),
        TaskFilter.overdue => !effectiveCompleted && _isTaskOverdue(task),
        TaskFilter.all => true,
      };

      final matchesSearch = task.title.toLowerCase().contains(searchQuery);

      return matchesFilter && matchesSearch;
    }).toList();
  }

  int getTaskCount(TaskFilter filter) {
    return getFilteredTasks(filter).length;
  }

  Color getFilterColor(TaskFilter filter) {
    return switch (filter) {
      TaskFilter.all => Colors.blue,
      TaskFilter.completed => Colors.green,
      TaskFilter.incomplete => Colors.orange,
      TaskFilter.overdue => Colors.red,
    };
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
              setState(() => searchQuery = "");
            },
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget buildTaskList(TaskFilter filter) {
    final filtered = getFilteredTasks(filter);
    
    if (isLoading) {
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
            onRefresh: () async => await fetchTasksFromFirestore(user!),
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
                                      color: getFilterColor(
                                        filter,
                                      ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${entry.value.length}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: getFilterColor(filter),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...entry.value.map(
                              (task) => ItemWidget(
                                item: task,
                                onEditDone:
                                    () async => await fetchTasksFromFirestore(user!),
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
    final added = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddTaskPage()),
    );
    if (added == true && user != null) {
      await fetchTasksFromFirestore(user!);
    }
  }

  Future<void> _navigateToAddMedication() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddMedicationPage(medicationManager: _medicationManager),
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Test alarm scheduled for 5 seconds!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
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
        drawer: MyDrawer(user: user, medicationManager: medicationManager),
        body: _authChecking
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