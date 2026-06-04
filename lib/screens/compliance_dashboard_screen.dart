import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:talkmate_ai/data/repositories/compliance_repository.dart';

class ComplianceDashboardScreen extends StatefulWidget {
  const ComplianceDashboardScreen({super.key});

  @override
  State<ComplianceDashboardScreen> createState() =>
      _ComplianceDashboardScreenState();
}

class _ComplianceDashboardScreenState extends State<ComplianceDashboardScreen> {
  final ComplianceRepository _repo = ComplianceRepository();
  bool _isLoading = true;

  Map<String, int> _rejectionStats = {};
  Map<String, bool> _consents = {};
  Map<String, dynamic>? _lastPurge;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _repo.getRejectionStats();
      final consents = await _repo.getMyConsents();
      final purge = await _repo.getLastPurgeLog();

      if (mounted) {
        setState(() {
          _rejectionStats = stats;
          _consents = consents;
          _lastPurge = purge;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compliance Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionTitle('Governance & Protection'),
                  const SizedBox(height: 10),
                  _buildKpiGrid(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('My Consent Status'),
                  _buildConsentList(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Data Retention'),
                  _buildPurgeInfo(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  }

  Widget _buildKpiGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _buildKpiCard(
            'Privacy Blocks',
            "${_rejectionStats['CONSENT_MISSING'] ?? 0}",
            Colors.orange,
            Icons.privacy_tip),
        _buildKpiCard('DND Shields', "${_rejectionStats['DND_ACTIVE'] ?? 0}",
            Colors.blue, Icons.do_not_disturb_on),
        _buildKpiCard('Flag Kills', "${_rejectionStats['FLAG_DISABLED'] ?? 0}",
            Colors.red, Icons.flag),
        _buildKpiCard('Safety Blocks', "${_rejectionStats['OTHER'] ?? 0}",
            Colors.grey, Icons.security),
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(title,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildConsentList() {
    if (_consents.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No explicit consents set. Using defaults.')));
    }

    return Card(
      child: Column(
        children: _consents.entries
            .map((e) => ListTile(
                  leading: Icon(e.value ? Icons.check_circle : Icons.cancel,
                      color: e.value ? Colors.green : Colors.red),
                  title: Text(e.key.toUpperCase()),
                  subtitle: Text(e.value ? 'Authorized' : 'Denied'),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildPurgeInfo() {
    if (_lastPurge == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.history, color: Colors.grey),
          title: Text('No purge history found'),
          subtitle: Text('System retains data according to policy.'),
        ),
      );
    }

    final meta = _lastPurge!['meta'] ?? {};
    final timestamp = DateTime.tryParse(_lastPurge!['created_at'] ?? '');
    final dateStr = timestamp != null
        ? DateFormat.yMMMd().add_jm().format(timestamp)
        : 'Unknown';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_delete, color: Colors.purple),
              const SizedBox(width: 8),
              Text('Last Auto-Purge: $dateStr',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const Divider(),
            ...[
              () {
                final metaMap = meta as Map<String, dynamic>;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        "Retention Days: ${metaMap['retention_days'] ?? 'N/A'}"),
                    Text("Logs Deleted: ${metaMap['deleted_logs'] ?? 0}"),
                    Text("Signals Deleted: ${metaMap['deleted_signals'] ?? 0}"),
                  ],
                );
              }()
            ],
          ],
        ),
      ),
    );
  }
}
