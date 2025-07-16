// import 'package:daily_planner/utils/performance_page/daily_tasks.dart';
// import 'package:daily_planner/utils/performance_page/total_tasks.dart';
// import 'package:flutter/material.dart';

// class AdvancedPerformancePage extends StatelessWidget {
//   const AdvancedPerformancePage({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Performance ghts')),
//       body: SafeArea(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // First section with debug boundary
//             Flexible(
//               flex: 1,
//               child: Container(
//                 decoration: BoxDecoration(
//                   border: Border.all(
//                     color: Colors.red,
//                     width: 2,
//                   ), // Debug border
//                 ),
//                 child: const _WidgetWrapper(child: TotalTasks()),
//               ),
//             ),

//             const Divider(height: 1, thickness: 1, color: Colors.grey),

//             // Second section with debug boundary
//             Flexible(
//               flex: 1,
//               child: Container(
//                 decoration: BoxDecoration(
//                   border: Border.all(
//                     color: Colors.blue,
//                     width: 2,
//                   ), // Debug border
//                 ),
//                 child: const _WidgetWrapper(child: DailyTasksStats()),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // Helper widget to catch rendering errors and provide constraints
// class _WidgetWrapper extends StatelessWidget {
//   final Widget child;

//   const _WidgetWrapper({required this.child});

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         return SingleChildScrollView(
//           physics: const AlwaysScrollableScrollPhysics(),
//           child: ConstrainedBox(
//             constraints: BoxConstraints(
//               minHeight: constraints.maxHeight,
//               minWidth: constraints.maxWidth,
//             ),
//             child: IntrinsicHeight(child: child),
//           ),
//         );
//       },
//     );
//   }
// }

import 'package:daily_planner/utils/performance_page/daily_tasks.dart';
import 'package:flutter/material.dart';

class AdvancedPerformancePage extends StatelessWidget {
  const AdvancedPerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: DailyTasksStats(),
      ),
    );
  }
}
