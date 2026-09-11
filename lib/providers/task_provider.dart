import 'dart:async';
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

  // Analytics & Dashboard Summary Getters
  int get totalTasksCount => _displayTasks.length;
  
  int get completedTasksCount =>
      _displayTasks.where((t) => getEffectiveCompletionStatus(t)).length;

  int get incompleteTasksCount =>
      _displayTasks.where((t) => !getEffectiveCompletionStatus(t) && !isTaskOverdue(t)).length;

  int get overdueTasksCount =>
      _displayTasks.where((t) => !getEffectiveCompletionStatus(t) && isTaskOverdue(t)).length;

  double get completionRate {
    if (_displayTasks.isEmpty) return 0.0;
    return (completedTasksCount / _displayTasks.length).clamp(0.0, 1.0);
  }

  void setSearchQuery(String query) {
    final trimmed = query.trim().toLowerCase();
    if (_searchQuery != trimmed) {
      _searchQuery = trimmed;
      notifyListeners();
    }
  }

  void clearSearch() {
    if (_searchQuery.isNotEmpty) {
      _searchQuery = "";
      notifyListeners();
    }
  }

  // Helper to get start of week (Monday)
  DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday;
    final daysFromMonday = (weekday + 6) % 7;
    return DateTime(date.year, date.month, date.day - daysFromMonday);
  }

  // Check and update ALL tasks' completion status when fetched
  Future<List<Task>> _updateTasksCompletionStatus(List<Task> fetchedTasks, User user, bool isFromCache) async {
    final List<Task> updatedTasks = [];
    final List<Task> tasksToReset = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekStart = _getWeekStart(now);
    final currentMonth = DateTime(now.year, now.month);

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
        final completedDate = task.completedAt!;
        bool needsReset = false;

        switch (task.taskType) {
          case 'DailyTask':
            final completedDay = DateTime(
              completedDate.year,
              completedDate.month,
              completedDate.day,
            );
            needsReset = completedDay.isBefore(today);
            break;

          case 'WeeklyTask':
            final completedWeekStart = _getWeekStart(completedDate);
            needsReset = completedWeekStart.isBefore(currentWeekStart);
            break;

          case 'MonthlyTask':
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

    // Update Firestore for tasks that need reset in background (only if we have true server data)
    // We don't want to overwrite the server based on stale offline cache!
    if (tasksToReset.isNotEmpty && !isFromCache) {
      _resetTasksInFirestore(tasksToReset, user);
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

    if (!task.isCompleted || task.completedAt == null) {
      return false;
    }

    final now = DateTime.now();
    final completedDate = task.completedAt!;

    switch (task.taskType) {
      case 'DailyTask':
        return completedDate.year == now.year &&
            completedDate.month == now.month &&
            completedDate.day == now.day;

      case 'WeeklyTask':
        final currentWeekStart = _getWeekStart(now);
        final completedWeekStart = _getWeekStart(completedDate);
        return completedWeekStart.year == currentWeekStart.year &&
            completedWeekStart.month == currentWeekStart.month &&
            completedWeekStart.day == currentWeekStart.day;

      case 'MonthlyTask':
        return completedDate.year == now.year &&
            completedDate.month == now.month;

      default:
        return task.isCompleted;
    }
  }

  bool isTaskOverdue(Task task) {
    if (getEffectiveCompletionStatus(task)) return false;
    if (task.date == null) return false;
    return task.date!.isBefore(DateTime.now());
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

      if (!matchesFilter) return false;

      if (_searchQuery.isEmpty) return true;
      return task.title.toLowerCase().contains(_searchQuery) ||
          task.detail.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  int getTaskCount(TaskFilter filter) {
    return getFilteredTasks(filter).length;
  }

  Color getFilterColor(TaskFilter filter) {
    return switch (filter) {
      TaskFilter.all => const Color(0xFF2563EB),
      TaskFilter.completed => const Color(0xFF10B981),
      TaskFilter.incomplete => const Color(0xFFF59E0B),
      TaskFilter.overdue => const Color(0xFFEF4444),
    };
  }

  StreamSubscription<QuerySnapshot>? _taskSubscription;

  Future<void> fetchTasks(User user, {bool showLoading = false}) async {
    if (showLoading || _tasks.isEmpty) {
      _isLoading = true;
      notifyListeners();
    }

    _taskSubscription?.cancel();
    
    _taskSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) async {
      final tasks = snapshot.docs
          .map((doc) => Task.fromMap(doc.data(), docId: doc.id))
          .toList();

      final updatedTasks = await _updateTasksCompletionStatus(tasks, user, snapshot.metadata.isFromCache);
      
      _tasks = tasks;
      _displayTasks = updatedTasks;
      _isLoading = false;
      notifyListeners();
    }, onError: (error) {
      debugPrint("Error listening to tasks: $error");
      _isLoading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _taskSubscription?.cancel();
    super.dispose();
  }

  // Optimistic UI state updater
  void updateTaskOptimistically(String docId, bool isCompleted, DateTime? completedAt) {
    final index = _displayTasks.indexWhere((t) => t.docId == docId);
    if (index != -1) {
      _displayTasks[index] = _displayTasks[index].copyWith(
        isCompleted: isCompleted,
        completedAt: completedAt,
      );
    }
    final taskIndex = _tasks.indexWhere((t) => t.docId == docId);
    if (taskIndex != -1) {
      _tasks[taskIndex] = _tasks[taskIndex].copyWith(
        isCompleted: isCompleted,
        completedAt: completedAt,
      );
    }
    notifyListeners();
  }

  void deleteTaskOptimistically(String docId) {
    _displayTasks.removeWhere((t) => t.docId == docId);
    _tasks.removeWhere((t) => t.docId == docId);
    notifyListeners();
  }

  void clearTasks() {
    _tasks.clear();
    _displayTasks.clear();
    _isLoading = false;
    notifyListeners();
  }
}
