import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/additemPage.dart';
import 'package:daily_planner/utils/Alarm_helper.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:daily_planner/utils/drawer.dart';
import 'package:daily_planner/utils/item.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum TaskFilter { all, completed, incomplete, overdue }

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

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((newUser) {
      user = newUser;
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
    setState(() => isLoading = true);
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('tasks')
              .orderBy('date')
              .get();

      final loadedTasks =
          snapshot.docs
              .map((doc) => Task.fromMap(doc.data(), docId: doc.id))
              .toList();

      if (mounted) {
        setState(() {
          tasks = loadedTasks;
          isLoading = false;
        });

        // Start foreground service only once
        if (!_serviceStarted) {
          _startForegroundService();
          _serviceStarted = true;
        }
      }
    } catch (e) {
      debugPrint("Firestore error: $e");
      if (mounted) setState(() => isLoading = false);
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

    return Column(
      children: [
        buildSearchBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => fetchTasksFromFirestore(user!),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                return ItemWidget(
                  item: filtered[index],
                  onEditDone: () => fetchTasksFromFirestore(user!),
                );
              },
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
        body:
            user == null
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
