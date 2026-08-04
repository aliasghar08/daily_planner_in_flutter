import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/utils/catalog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TaskProvider extends ChangeNotifier {
  List<Task> _tasks = [];
  List<Task> _displayTasks = [];
  bool _isLoading = true;
  String _searchQuery = "";

  List<Task> get tasks => _tasks;
  List<Task> get displayTasks => _displayTasks;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  void setSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = "";
    notifyListeners();
  }

  // Helper to get start of week (Monday)
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    final daysFromMonday = (weekday + 6) % 7;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  // Check and update ALL tasks' completion status when fetched
  Future<List<Task>> _updateTasksCompletionStatus(List<Task> fetchedTasks, User user) async {
    final List<Task> updatedTasks = [];
    final List<Task> tasksToReset = [];

    for (var task in fetchedTasks) {
      Task updatedTask = Task(
        docId: task.docId,
        title: task.title,
        detail: task.detail,
        date: task.date,
        createdAt: task.createdAt,
        isCompleted: task.isCompleted,
        completedAt: task.completedAt,
        taskType: task.taskType,
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
          updatedTask = updatedTask.copyWith(
            isCompleted: false,
            completedAt: null,
          );
          tasksToReset.add(task);
        }
      }

      updatedTasks.add(updatedTask);
    }

    // Update Firestore for tasks that need reset
    if (tasksToReset.isNotEmpty) {
      await _resetTasksInFirestore(tasksToReset, user);
    }

    return updatedTasks;
  }

  // Reset tasks in Firestore
  Future<void> _resetTasksInFirestore(List<Task> tasksToReset, User user) async {
    try {
      final batch = FirebaseFirestore.instance.batch();

      for (var task in tasksToReset) {
        final taskRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
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

  // Get effective completion status for display (synchronous)
  bool getEffectiveCompletionStatus(Task task) {
    if (task.taskType == 'oneTime') {
      return task.isCompleted;
    }

    if (!task.isCompleted) {
      return false;
    }

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

  bool isTaskOverdue(Task task) {
    final taskToCheck = _displayTasks.firstWhere(
      (t) => t.docId == task.docId,
      orElse: () => task,
    );

    if (getEffectiveCompletionStatus(taskToCheck)) return false;

    if (task.date == null) return false;

    final now = DateTime.now();
    return task.date!.isBefore(now);
  }

  List<Task> getFilteredTasks(TaskFilter filter) {
    return _displayTasks.where((task) {
      final effectiveCompleted = getEffectiveCompletionStatus(task);

      final matchesFilter = switch (filter) {
        TaskFilter.completed => effectiveCompleted,
        TaskFilter.incomplete => !effectiveCompleted && !isTaskOverdue(task),
        TaskFilter.overdue => !effectiveCompleted && isTaskOverdue(task),
        TaskFilter.all => true,
      };

      final matchesSearch = task.title.toLowerCase().contains(_searchQuery);

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

  Future<void> fetchTasks(User user) async {
    _isLoading = true;
    notifyListeners();

    List<Task> allTasks = [];

    try {
      // Try cache first
      final cachedSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tasks')
          .orderBy('createdAt', descending: true)
          .get(const GetOptions(source: Source.cache));

      allTasks = cachedSnapshot.docs
          .map((doc) => Task.fromMap(doc.data(), docId: doc.id))
          .toList();

      debugPrint("✅ Loaded ${allTasks.length} tasks from cache");

      // Update completion status and get display tasks
      final updatedTasks = await _updateTasksCompletionStatus(allTasks, user);

      _tasks = allTasks;
      _displayTasks = updatedTasks;
      _isLoading = false;
      notifyListeners();
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

      final serverTasks = serverSnapshot.docs
          .map((doc) => Task.fromMap(doc.data(), docId: doc.id))
          .toList();

      debugPrint("✅ Loaded ${serverTasks.length} tasks from server");

      // Update completion status and get display tasks
      final updatedTasks = await _updateTasksCompletionStatus(serverTasks, user);

      _tasks = serverTasks;
      _displayTasks = updatedTasks;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint("Server fetch failed (offline?): $e");

      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void clearTasks() {
    _tasks.clear();
    _displayTasks.clear();
    _isLoading = false;
    notifyListeners();
  }
}
