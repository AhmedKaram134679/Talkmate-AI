import 'package:flutter/material.dart';

/// Wraps the application to listen for global events like Incoming Calls.
/// Note: Navigation logic has been moved to CallManager for central orchestration.
class MainWrapper extends StatefulWidget {
  final Widget child;
  const MainWrapper({super.key, required this.child});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  @override
  void initState() {
    super.initState();
    // Logic moved to CallManager for central orchestration.
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
