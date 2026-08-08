# 🗓️ Daily Planner - Flutter App

Welcome to **Daily Planner**, a personal productivity and habit tracking app built with Flutter. Whether you're organizing daily tasks, tracking critical medicine intake schedules, or analyzing performance over time, Daily Planner helps you stay focused and consistent.

## ✨ Features

- ✅ **Add, Edit, and Delete Tasks**
  - Create one-time or recurring tasks (daily, weekly, monthly)
  - Custom titles, descriptions, and categories

- 💊 **Medication & Habit Tracking (Waking Day Logic)**
  - Reliable tracking for medicine intake and late-night habits.
  - Implements a logical "Waking Day vs. Calendar Day" boundary (e.g., 4:00 AM cutoff).
  - Ensures that medications taken or tasks completed after midnight still count toward your active waking day, aligning perfectly with human sleep cycles rather than strict calendar dates.

- 🔔 **Alarms & Notifications**
  - Schedule alarms using `android_alarm_manager_plus`, displayed via a native Kotlin implementation
  - Smart alarm logic integrated specifically with each task type
  - Multiple configurable alarms for a single task

- 📈 **Advanced Performance Analytics**
  - View overall completion rates, longest streaks, and breakdowns by category
  - Interactive visualization using bar and pie charts

- 🔁 **Auto Reset Logic**
  - Automatically resets tasks based on their frequency (daily/weekly/monthly)
  - Earn Completion Stamps for maintaining streaks on recurring tasks

- 🔍 **Search Functionality**
  - Instantly search tasks locally without reloading from Firestore

- ☁️ **Firebase Integration & Offline Support**
  - Real-time storage and sync using Cloud Firestore
  - Built-in caching stores changes locally when offline and pushes them to Cloud Firestore immediately once connectivity is restored

## 🛠️ Tech Stack

- **Frontend:** Flutter (Dart)
- **Backend:** Firebase Cloud Firestore
- **Native Android:** Kotlin (Custom Alarm implementations)

## 🧱 Project Structure

- `main.dart` – Entry point
- `screens/` – All UI screens (Home, Add/Edit Task, Advanced Performance, etc.)
- `models/` – Task models (DailyTask, WeeklyTask, MonthlyTask, etc.)
- `services/` – Firebase, Notification, Alarm, and Reset logic
- `widgets/` – Reusable UI components (MyDrawer, charts, etc.)
