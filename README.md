# 🗓️ Daily Planner - Flutter App

Welcome to **Daily Planner**, a personal productivity and habit tracking app built with Flutter. Whether you're organizing daily tasks, tracking long-term habits, or analyzing performance over time, Daily Planner helps you stay focused and consistent.

## ✨ Features

- ✅ **Add, Edit, and Delete Tasks**
  - Create one-time or recurring tasks (daily, weekly, monthly)
  - Custom titles, descriptions, and categories

- 🔔 **Alarms & Notifications**
  - Schedule alarms using android_alarm_manager_plus and showed them using native kotlin implementation
  - Alarm logic integrated with each task type
  - Multiple alarms for a task

- 📈 **Advanced Performance Analytics**
  - View overall completion rates, longest streaks, and breakdowns by category
  - Interactive charts (bar and pie)

- 🔁 **Auto Reset Logic**
  - Automatically resets tasks based on their frequency (daily/weekly/monthly)
  - Get Completion stamps in case of recurring tasks

- 🔍 **Search Functionality**
  - Instantly search tasks without reloading from Firestore

- ☁️ **Firebase Integration**
  - Real-time storage and sync using Cloud Firestore
  - Used cache to store changes and pushed them to Cloud Firestore when online in case user was offline during the change

## 🧱 Project Structure

- `main.dart` – Entry point
- `screens/` – All UI screens (Home, Add/Edit Task, Advanced Performance, etc.)
- `models/` – Task models (DailyTask, WeeklyTask, MonthlyTask, etc.)
- `services/` – Firebase, Notification, Alarm, and Reset logic
- `widgets/` – Reusable UI components (MyDrawer, charts, etc.)

## 🛠️ Setup Instructions

1. **Clone the repository**
   ```bash
   git clone https://github.com/aliasghar08/daily_planner_in_flutter.git
   cd daily-planner

