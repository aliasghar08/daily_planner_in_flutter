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
  bool _authChecking = true;

  @override
  void initState() {
    super.initState();

    FirebaseAuth.instance.authStateChanges().listen((newUser) {
      setState(() {
        user = newUser;
        _authChecking = false;
      });
      
      if (user != null) {
        fetchTasksFromFirestore(user!);
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
        isLoading = false;
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
          tasks = serverTasks;
        });
      }
    } catch (e) {
      debugPrint("Server fetch failed (offline?): $e");
    }
  }

  Future<void> _startForegroundService() async {
    try {
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
        builder: (ctx) => AlertDialog(
          title: const Text(
            "Allow Alarm Permission",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "We need permission to schedule exact alarms for your task reminders and notifications.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Not Now"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text("Allow"),
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
      final taskDate = (task.date is Timestamp)
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search tasks...',
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear_rounded, color: Colors.grey),
              onPressed: () {
                _searchController.clear();
                setState(() => searchQuery = "");
              },
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(TaskFilter filter) {
    final String message;
    final IconData icon;
    final String description;

    switch (filter) {
      case TaskFilter.completed:
        message = "No completed tasks";
        icon = Icons.check_circle_outline;
        description = "Tasks you complete will appear here";
        break;
      case TaskFilter.incomplete:
        message = "No pending tasks";
        icon = Icons.incomplete_circle_outlined;
        description = "All your tasks are done! Great job!";
        break;
      case TaskFilter.overdue:
        message = "No overdue tasks";
        icon = Icons.schedule;
        description = "You're on top of your schedule!";
        break;
      case TaskFilter.all:
        message = "No tasks yet";
        icon = Icons.task_alt;
        description = "Create your first task to get started";
        break;
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (filter == TaskFilter.all && user != null) ...[
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _navigateToAddTask,
                      icon: const Icon(Icons.add),
                      label: const Text("Create Your First Task"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskList(TaskFilter filter) {
    final filtered = getFilteredTasks(filter);
    
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              "Loading your tasks...",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (filtered.isEmpty) {
      return _buildEmptyState(filter);
    }

    // Group tasks by type for ALL filters, not just TaskFilter.all
    final Map<String, List<Task>> groupedTasks = {
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
          // Handle any unexpected task types by adding to One-Time
          groupedTasks["One-Time Tasks"]!.add(task);
      }
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => fetchTasksFromFirestore(user!),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: groupedTasks.entries
                  .where((entry) => entry.value.isNotEmpty)
                  .map((entry) {
                return _buildTaskGroup(entry.key, entry.value);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskGroup(String title, List<Task> tasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              _buildGroupIcon(title),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${tasks.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...tasks.map(
          (task) => ItemWidget(
            item: task,
            onEditDone: () => fetchTasksFromFirestore(user!),
            searchQuery: searchQuery,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupIcon(String title) {
    final IconData icon;
    final Color color;

    switch (title) {
      case "One-Time Tasks":
        icon = Icons.push_pin;
        color = Colors.blue;
        break;
      case "Daily Tasks":
        icon = Icons.loop;
        color = Colors.green;
        break;
      case "Weekly Tasks":
        icon = Icons.calendar_today;
        color = Colors.orange;
        break;
      case "Monthly Tasks":
        icon = Icons.date_range;
        color = Colors.purple;
        break;
      default:
        icon = Icons.task;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  Future<void> _navigateToAddTask() async {
    final added = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddTaskPage()),
    );
    if (added == true && user != null) {
      fetchTasksFromFirestore(user!);
    }
  }

  Widget _buildAuthChecking() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              "Checking authentication...",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 80,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 24),
              Text(
                "Welcome to Daily Planner",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Please login to manage your tasks and stay organized",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                icon: const Icon(Icons.login),
                label: const Text("Login to Continue"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            "My Tasks",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          elevation: 0,
          bottom: TabBar(
            isScrollable: true,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            labelColor: Theme.of(context).colorScheme.onPrimary,
            unselectedLabelColor: Colors.grey.shade700,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            tabs: const [
              Tab(text: "All"),
              Tab(text: "Completed"),
              Tab(text: "Incomplete"),
              Tab(text: "Overdue"),
            ],
          ),
        ),
        drawer: MyDrawer(user: user),
        body: _authChecking
            ? _buildAuthChecking()
            : user == null
                ? _buildLoginPrompt()
                : TabBarView(
                    children: [
                      _buildTaskList(TaskFilter.all),
                      _buildTaskList(TaskFilter.completed),
                      _buildTaskList(TaskFilter.incomplete),
                      _buildTaskList(TaskFilter.overdue),
                    ],
                  ),
        floatingActionButton: user == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _navigateToAddTask,
                icon: const Icon(Icons.add_rounded),
                label: const Text("Add Task"),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
      ),
    );
  }
}