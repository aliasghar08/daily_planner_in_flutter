import 'package:cloud_firestore/cloud_firestore.dart';

class CatlalogModel {
  static List<Task> items = [
    Task(
      docId: '1',
      title: "Get the meal",
      detail: "I need to have my dinner done on time",
      date: DateTime.now(),
      isCompleted: true,
      completedAt: DateTime.now(), notificationTimes: [], fcmToken: '',
    ),
    Task(
      docId: '2',
      title: "Get your work done before deadline",
      detail: "I need to get my work done before the deadline at any cost",
      date: DateTime.now(),
      isCompleted: true,
      completedAt: DateTime.now(), notificationTimes: [], fcmToken: '',
    ),
  ];
}

class TaskEdit {
  final DateTime timestamp;
  final String? note;

  TaskEdit({required this.timestamp, this.note});

  factory TaskEdit.fromMap(Map<String, dynamic> map) {
    DateTime ts;
    if (map['timestamp'] is Timestamp) {
      ts = (map['timestamp'] as Timestamp).toDate();
    } else {
      ts = DateTime.tryParse(map['timestamp']) ?? DateTime.now();
    }

    return TaskEdit(timestamp: ts, note: map['note']);
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': Timestamp.fromDate(timestamp),
      if (note != null) 'note': note,
    };
  }
}

class Task {
  String? docId;
  String title;
  String detail;
  DateTime date;
  bool isCompleted;
  DateTime createdAt;
  DateTime? completedAt;
  List<TaskEdit> editHistory;
  String taskType;
  List<DateTime> notificationTimes;



  Task({
    this.docId,
    required this.title,
    required this.detail,
    required this.date,
    required this.isCompleted,
    
    DateTime? createdAt,
    this.completedAt,
    List<TaskEdit>? editHistory,
    this.taskType = 'oneTime',
    List<DateTime>? notificationTimes, String? fcmToken,
  }) : createdAt = createdAt ?? DateTime.now(),
       editHistory = editHistory ?? [], 
       notificationTimes = notificationTimes ?? []; 

    


  factory Task.fromMap(Map<String, dynamic> map, {String? docId}) {
    List<TaskEdit> history = [];
    if (map['editHistory'] is List) {
      history =
          (map['editHistory'] as List)
              .map((e) => TaskEdit.fromMap(Map<String, dynamic>.from(e)))
              .toList();
    }

    DateTime? parseTimeNullable(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    DateTime parseTime(dynamic val) {
      return parseTimeNullable(val) ?? DateTime.now();
    }

    List<DateTime> parseNotificationTimes(dynamic val) {
      if (val == null || val is! List) return [];
      return val
          .map((e) {
            if (e is Timestamp) return e.toDate();
            if (e is String) return DateTime.tryParse(e);
            return null;
          })
          .whereType<DateTime>()
          .toList();
    }

    return Task(
      docId: docId,
      title: map['title'] ?? '',
      detail: map['detail'] ?? '',
      date: parseTime(map['date']),
      isCompleted: map['isCompleted'] ?? false,
      createdAt: parseTime(map['createdAt']),
      completedAt: parseTimeNullable(map['completedAt']),
      editHistory: history,
      taskType: map['taskType'] ?? 'oneTime', // ✅ Fallback for old records
      notificationTimes: parseNotificationTimes(map['notificationTimes']), fcmToken: null
    );
  }

  Map<String, dynamic> toMap() {
    final data = {
      'id': docId,
      'title': title,
      'detail': detail,
      'date': Timestamp.fromDate(date),
      'isCompleted': isCompleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'editHistory': editHistory.map((e) => e.toMap()).toList(),
      'taskType': taskType,
      'notificationTimes':
          notificationTimes
              .map((dt) => Timestamp.fromDate(dt))
              .toList(), // ✅ Add this line
    };

    if (completedAt != null) {
      data['completedAt'] = Timestamp.fromDate(completedAt!);
    }

    

    return data;
  }

  String get type => 'Task';

  Iterable? get completionStamps => null;
  
  get fcmToken => null;

  Task copyWith({
    String? docId,
    String? title,
    String? detail,
    DateTime? date,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? completedAt,
    List<TaskEdit>? editHistory,
    String? taskType,
    List<DateTime>? notificationTimes,
    String? fcmToken
  }) {
    return Task(
      docId: docId ?? this.docId,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      date: date ?? this.date,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      editHistory: editHistory ?? this.editHistory,
      taskType: taskType ?? this.taskType,
      notificationTimes: notificationTimes ?? this.notificationTimes,
      fcmToken: this.fcmToken,
    );
  }
}

class DailyTask extends Task {
  final bool morning;
  @override
  final List<DateTime> completionStamps;

  DailyTask({
    required super.docId,
    required super.title,
    required super.detail,
    required super.date,
    required super.isCompleted,
    required super.createdAt,
    super.completedAt,
    this.morning = true,
    List<DateTime>? completionStamps,
    required List<DateTime> notificationTimes,
    String? fcmToken
    
  }) : completionStamps = completionStamps ?? [],
       super(notificationTimes: notificationTimes, fcmToken: fcmToken);

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'type': 'DailyTask',
    'taskType': 'DailyTask',
    'morning': morning,
    'completionStamps':
        completionStamps.map((d) => Timestamp.fromDate(d)).toList(),
    'notificationTimes':
        notificationTimes.map((dt) => Timestamp.fromDate(dt)).toList(),
  };

  factory DailyTask.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    List<DateTime> parseStamps(dynamic list) {
      if (list == null) return [];
      return List<DateTime>.from((list as List).map(parseTime));
    }

    List<DateTime> parseNotificationTimes(dynamic list) {
      if (list == null || list is! List) return [];
      return list
          .map((e) {
            if (e is Timestamp) return e.toDate();
            if (e is String) return DateTime.tryParse(e);
            return null;
          })
          .whereType<DateTime>()
          .toList();
    }

    return DailyTask(
      docId: docId,
      title: map['title'],
      detail: map['detail'],
      date: parseTime(map['date']),
      isCompleted: map['isCompleted'],
      createdAt: parseTime(map['createdAt']),
      completedAt:
          map['completedAt'] != null ? parseTime(map['completedAt']) : null,
      morning: map['morning'] ?? true,
      completionStamps: parseStamps(map['completionStamps']),
      notificationTimes: parseNotificationTimes(map['notificationTimes']),
      fcmToken: map['fcmToken'] as String?
    );
  }

  Null get intervalDays => null;

  bool shouldResetToday() {
    if (completedAt == null) return true;

    final lastCompleted = completedAt!;
    final now = DateTime.now();

    return !(lastCompleted.year == now.year &&
        lastCompleted.month == now.month &&
        lastCompleted.day == now.day);
  }
}

class WeeklyTask extends Task {
  @override
  final List<DateTime> completionStamps;

  WeeklyTask({
    required super.docId,
    required super.title,
    required super.detail,
    required super.date,
    required super.isCompleted,
    required super.createdAt,
    super.completedAt,
    List<DateTime>? completionStamps,
    required List<DateTime> notificationTimes,
    String? fcmToken,
  }) : completionStamps = completionStamps ?? [],
       super(notificationTimes: notificationTimes, fcmToken: fcmToken);

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'type': 'WeeklyTask',
    'taskType': 'WeeklyTask',
    'completionStamps':
        completionStamps.map((d) => Timestamp.fromDate(d)).toList(),
    'notificationTimes':
        notificationTimes.map((dt) => Timestamp.fromDate(dt)).toList(),
  };

  factory WeeklyTask.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    List<DateTime> parseStamps(dynamic list) {
      if (list == null) return [];
      return List<DateTime>.from((list as List).map(parseTime));
    }

    List<DateTime> parseNotificationTimes(dynamic list) {
      if (list == null || list is! List) return [];
      return list
          .map((e) {
            if (e is Timestamp) return e.toDate();
            if (e is String) return DateTime.tryParse(e);
            return null;
          })
          .whereType<DateTime>()
          .toList();
    }

    return WeeklyTask(
      docId: docId,
      title: map['title'],
      detail: map['detail'],
      date: parseTime(map['date']),
      isCompleted: map['isCompleted'],
      createdAt: parseTime(map['createdAt']),
      completedAt:
          map['completedAt'] != null ? parseTime(map['completedAt']) : null,
      completionStamps: parseStamps(map['completionStamps']),
      notificationTimes: parseNotificationTimes(map['notificationsTimes']),
      fcmToken: map['fcmToken'] as String?
    );
  }


  bool shouldResetThisWeek() {
    if (completedAt == null) return true;

    final now = DateTime.now();
    final last = completedAt!;
    return !(now.difference(last).inDays < 7 && now.weekday != last.weekday);
  }
}

class MonthlyTask extends Task {
  final int dayOfMonth;
  @override
  final List<DateTime> completionStamps;

  MonthlyTask({
    required super.docId,
    required super.title,
    required super.detail,
    required super.date,
    required super.isCompleted,
    required super.createdAt,
    super.completedAt,
    required this.dayOfMonth,
    List<DateTime>? completionStamps,
    required List<DateTime> notificationTimes,
    String? fcmToken,
  }) : completionStamps = completionStamps ?? [],
       super(notificationTimes: notificationTimes, fcmToken: fcmToken);

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'type': 'MonthlyTask',
    'taskType': 'MonthlyTask',
    'dayOfMonth': dayOfMonth,
    'completionStamps':
        completionStamps.map((d) => Timestamp.fromDate(d)).toList(),
        'notificationTimes': notificationTimes.map((dt) => Timestamp.fromDate(dt)).toList(),

  };

  factory MonthlyTask.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    List<DateTime> parseStamps(dynamic list) {
      if (list == null) return [];
      return List<DateTime>.from((list as List).map(parseTime));
    }

    List<DateTime> parseNotificationTimes(dynamic list) {
  if (list == null || list is! List) return [];
  return list.map((e) {
    if (e is Timestamp) return e.toDate();
    if (e is String) return DateTime.tryParse(e);
    return null;
  }).whereType<DateTime>().toList();
}


    return MonthlyTask(
      docId: docId,
      title: map['title'],
      detail: map['detail'],
      date: parseTime(map['date']),
      isCompleted: map['isCompleted'],
      createdAt: parseTime(map['createdAt']),
      completedAt:
          map['completedAt'] != null ? parseTime(map['completedAt']) : null,
      dayOfMonth: map['dayOfMonth'],
      completionStamps: parseStamps(map['completionStamps']),
      notificationTimes: parseNotificationTimes(map['notificationTimes']),
      fcmToken: map['fcmToken'] as String
    );
  }

  bool shouldResetThisMonth() {
    if (completedAt == null) return true;

    final now = DateTime.now();
    final last = completedAt!;

    return !(now.year == last.year &&
        now.month == last.month &&
        now.day == last.day);
  }
}

/// Helper to determine correct subclass when decoding
Task parseTaskFromMap(Map<String, dynamic> map, {String? docId}) {
  switch (map['type']) {
    case 'DailyTask':
      return DailyTask.fromMap(map, docId: docId);
    case 'WeeklyTask':
      return WeeklyTask.fromMap(map, docId: docId);
    case 'MonthlyTask':
      return MonthlyTask.fromMap(map, docId: docId);
    default:
      return Task.fromMap(map, docId: docId);
  }
}

DateTime getNextOccurrence(Task task) {
  switch (task.taskType) {
    case 'daily':
      return task.date.add(const Duration(days: 1));
    case 'weekly':
      return task.date.add(const Duration(days: 7));
    case 'monthly':
      return DateTime(task.date.year, task.date.month + 1, task.date.day);
    default:
      return task.date;
  }
}
