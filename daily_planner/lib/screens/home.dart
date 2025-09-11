import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/additemPage.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
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

class MyHome extends StatefulWidget {
  const MyHome({super.key});

  @override
  State<MyHome> createState() => _MyHomeState();
}

class _MyHomeState extends State<MyHome> {
  List<Task> tasks = [];
  bool isLoading = true;
  User? user;
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = "";
  bool _serviceStarted = false;
  bool _authChecking = true; // Added to track auth state

  @override
  void initState() {
    super.initState();

    FirebaseAuth.instance.authStateChanges().listen((newUser) {
      setState(() {
        user = newUser;
        _authChecking = false; // Auth check complete
      });
      
      if (user != null) {
        fetchTasksFromFirestore(user!); // async, non-blocking
        maybeRequestAlarmPermission();
      }
    });

    _searchController.addListener(() {
      setState(() {
        searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  Future<void> fetchTasksFromFirestore(User user) async {
    if (!mounted) return;

    List<Task> allTasks = [];

    // 1. Load cached tasks first (works offline)
    try {
      final cachedSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .orderBy('date')
          .get(const GetOptions(source: Source.cache));

      allTasks = cachedSnapshot.docs
          .map((doc) => Task.fromMap(doc.data(), docId: doc.id))
          .toList();
    } catch (e) {
      debugPrint("Error loading cached tasks: $e");
    }

    if (mounted) {
      setState(() {
        tasks = allTasks;
        isLoading = false; // show UI immediately
      });
    }

    // 2. Fetch from server in background (if online)
    try {
      final serverSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .orderBy('date')
          .get(const GetOptions(source: Source.server));

      final serverTasks = serverSnapshot.docs
          .map((doc) => Task.fromMap(doc.data(), docId: doc.id))
          .toList();

      if (mounted) {
        setState(() {
          tasks = serverTasks; // update UI with fresh data
        });
      }
    } catch (e) {
      debugPrint("Server fetch failed (offline?): $e");
    }
  }

  Future<void> _startForegroundService() async {
    try {
      //  await NativeAlarmHelper.startForegroundService();
      debugPrint("Foreground service started.");
    } catch (e) {
      debugPrint("Error starting foreground service: $e");
    }
  }

  Future<void> maybeRequestAlarmPermission() async {
    final hasPermission = await NativeAlarmHelper.checkExactAlarmPermission();
    if (!hasPermission) {
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text("Allow Alarm Permission"),
              content: const Text(
                "We need permission to schedule exact alarms for your tasks.",
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
        await NativeAlarmHelper.requestExactAlarmPermission();
      }
    }
  }

  List<Task> getFilteredTasks(TaskFilter filter) {
    final now = DateTime.now();

    return tasks.where((task) {
      final taskDate =
          (task.date is Timestamp)
              ? (task.date as Timestamp).toDate()
              : task.date;

      final matchesFilter = switch (filter) {
        TaskFilter.completed => task.isCompleted,
        TaskFilter.incomplete => !task.isCompleted && taskDate.isAfter(now),
        TaskFilter.overdue => !task.isCompleted && taskDate.isBefore(now),
        TaskFilter.all => true,
      };

      final matchesSearch = task.title.toLowerCase().contains(searchQuery);

      return matchesFilter && matchesSearch;
    }).toList();
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
          const Expanded(child: Center(child: Text("No tasks found."))),
        ],
      );
    }

    // Group tasks by type
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
      }
    }

    return Column(
      children: [
        buildSearchBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => fetchTasksFromFirestore(user!),
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
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ...entry.value.map(
                              (task) => ItemWidget(
                                item: task,
                                onEditDone:
                                    () => fetchTasksFromFirestore(user!),
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
      fetchTasksFromFirestore(user!);
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
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: "All"),
              Tab(text: "Completed"),
              Tab(text: "Incomplete"),
              Tab(text: "Overdue"),
            ],
          ),
        ),
        drawer: MyDrawer(user: user),
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
        floatingActionButton:
            user == null
                ? null
                : FloatingActionButton.extended(
                    onPressed: _navigateToAddTask,
                    icon: const Icon(Icons.add),
                    label: const Text("Add Task"),
                  ),
      ),
    );
  }
}