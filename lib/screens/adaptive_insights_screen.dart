import 'package:flutter/material.dart';

class AdaptiveInsightsScreen extends StatelessWidget {
  const AdaptiveInsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // In a real app, this would fetch from the adaptive_routing_stats view
    // For now, we mock the UI to demonstrate the dashboard
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adaptive Insights'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHealthrCard(),
            const SizedBox(height: 20),
            const Text(
              'Recent Auto-Healing Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _buildActionTile('Throttled Notification', 'Low Open Rate (< 5%)',
                '10 mins ago'),
            _buildActionTile('Priority Downgrade', 'DND Active', '1 hour ago'),
            _buildActionTile(
                'Skipped (Foreground)', 'User Active', '2 hours ago'),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthrCard() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.health_and_safety, color: Colors.green, size: 32),
                SizedBox(width: 10),
                Text(
                  'System Health: Excellent',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
                'Your notification stream is optimized. You are receiving high-priority messages instantly.'),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('Open Rate', '45%'),
                _buildStat('Optimization', 'Active'),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildActionTile(String title, String reason, String time) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.auto_fix_high, color: Colors.blueAccent),
        title: Text(title),
        subtitle: Text(reason),
        trailing: Text(time),
      ),
    );
  }
}
