import 'package:daily_planner/screens/login.dart';
import 'package:daily_planner/screens/performance.dart';
import 'package:daily_planner/screens/settings.dart';
import 'package:daily_planner/utils/performance_page/daily_tasks.dart';
import 'package:daily_planner/utils/performance_page/total_tasks.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MyDrawer extends StatefulWidget {
  final User? user;

  const MyDrawer({super.key, required this.user});

  @override
  State<MyDrawer> createState() => _MyDrawerState();
}

class _MyDrawerState extends State<MyDrawer> {
  bool _isinsightsexpanded = false;
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(widget.user?.displayName ?? 'Guest User'),
              accountEmail: Text(widget.user?.email ?? 'Not signed in'),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 40, color: Colors.blueAccent),
              ),
              decoration: BoxDecoration(color: Colors.blueAccent),
            ),
            ListTile(
              leading: Icon(Icons.home),
              title: Text('Home'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Settings'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.logout),
              title: Text('Logout'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Logged out")));
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => LoginPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.perm_device_information),
              title: const Text("Insights"),
              trailing: Icon(
                _isinsightsexpanded ? Icons.expand_more : Icons.expand_less,
              ),
              onTap: () {
                setState(() {
                  _isinsightsexpanded = !_isinsightsexpanded;
                });
              },
            ),
        
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.fastOutSlowIn,
              child: Visibility(
                visible: _isinsightsexpanded,
                child: Column(
                  children: [
                    ListTile(
                      leading: const SizedBox(width: 40),
                      title: const Text("Daily Tasks Stats"),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DailyTasksStats(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const SizedBox(width: 40),
                      title: const Text("Total Tasks Stats"),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TotalTasks(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
