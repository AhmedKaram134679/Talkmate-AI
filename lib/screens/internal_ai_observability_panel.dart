import 'package:flutter/material.dart';

class InternalAIObservabilityPanel extends StatelessWidget {
  final List<Map<String, dynamic>> decisionTrends;
  final double shadowConcordance;
  final List<Map<String, dynamic>> activeGuardrails;

  const InternalAIObservabilityPanel({
    super.key,
    required this.decisionTrends,
    required this.shadowConcordance,
    required this.activeGuardrails,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('AI Observability Panel',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildQuickStats(),
            const SizedBox(height: 24),
            _buildSectionHeader('Shadow Model Concordance'),
            const SizedBox(height: 12),
            _buildShadowGauge(),
            const SizedBox(height: 24),
            _buildSectionHeader('Decision Trends'),
            const SizedBox(height: 12),
            _buildTrendList(),
            const SizedBox(height: 24),
            _buildSectionHeader('Active Guardrails'),
            const SizedBox(height: 12),
            _buildGuardrailList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
            child: _buildStatCard(
                'Total Decisions', '1,240', Icons.analytics, Colors.blue)),
        const SizedBox(width: 12),
        Expanded(
            child: _buildStatCard(
                'Learning Status', 'ACTIVE', Icons.psychology, Colors.green)),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildShadowGauge() {
    final percentage = (shadowConcordance * 100).toStringAsFixed(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: shadowConcordance,
                  strokeWidth: 10,
                  backgroundColor: Colors.white10,
                  color: shadowConcordance > 0.9 ? Colors.green : Colors.orange,
                ),
              ),
              Text('$percentage%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Shadow model successfully matched live decisions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendList() {
    return Column(
      children: decisionTrends.map((trend) {
        final color = trend['color'] as Color;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(width: 4, height: 30, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trend['type'],
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    Text('${trend['count']} items',
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
              Text('${trend['percentage']}%',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGuardrailList() {
    return Column(
      children: activeGuardrails.map((guard) {
        return ExpansionTile(
          collapsedBackgroundColor: Colors.white.withValues(alpha: 0.02),
          backgroundColor: Colors.white.withValues(alpha: 0.05),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(guard['scope'],
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text('Mode: ${guard['mode']}',
              style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGuardDetail('Max Drift', guard['max_drift']),
                  _buildGuardDetail('Floor Confidence', guard['min_floor']),
                  _buildGuardDetail('Status', guard['status'],
                      color: Colors.green),
                ],
              ),
            )
          ],
        );
      }).toList(),
    );
  }

  Widget _buildGuardDetail(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: color ?? Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
