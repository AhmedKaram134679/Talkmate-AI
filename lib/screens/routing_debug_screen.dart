import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:talkmate_ai/data/models/routing_log_model.dart';
import 'package:talkmate_ai/data/repositories/routing_log_repository.dart';

class RoutingDebugScreen extends StatefulWidget {
  const RoutingDebugScreen({super.key});

  @override
  State<RoutingDebugScreen> createState() => _RoutingDebugScreenState();
}

class _RoutingDebugScreenState extends State<RoutingDebugScreen> {
  final RoutingLogRepository _repository = RoutingLogRepository();
  List<RoutingLogModel> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await _repository.getLogs();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routing Debugger'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(child: Text('No routing logs found yet.'))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    return _buildLogTile(log);
                  },
                ),
    );
  }

  Widget _buildLogTile(RoutingLogModel log) {
    Color statusColor;
    IconData statusIcon;

    switch (log.decision) {
      case 'sent':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'silent':
        statusColor = Colors.amber;
        statusIcon = Icons.do_not_disturb_on;
        break;
      case 'skipped':
        statusColor = Colors.redAccent;
        statusIcon = Icons.remove_circle_outline;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ExpansionTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(
          log.reason ?? log.decision.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${DateFormat('HH:mm:ss').format(log.createdAt)} • ${log.deviceId.length > 8 ? log.deviceId.substring(0, 8) : log.deviceId}${log.deviceId.length > 8 ? '...' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: log.priority != null
            ? Chip(
                label:
                    Text(log.priority!, style: const TextStyle(fontSize: 10)),
                backgroundColor: log.priority == 'high'
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.1),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Decision: ${log.decision}',
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Device Metadata:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(log.meta.toString()),
              ],
            ),
          )
        ],
      ),
    );
  }
}
