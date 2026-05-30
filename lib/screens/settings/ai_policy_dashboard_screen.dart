import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/controllers/notification_ai_settings_controller.dart';
import 'package:talkmate_ai/data/models/ai_policy_model.dart';

class AiPolicyDashboardScreen extends StatelessWidget {
  const AiPolicyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<NotificationAiSettingsController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سياسات الذكاء الاصطناعي'),
        centerTitle: true,
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final scopes = controller.aiScopes;
        if (scopes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.policy_outlined,
                    size: 64, color: theme.disabledColor),
                const SizedBox(height: 16),
                const Text('لا توجد نطاقات سياسة نشطة'),
              ],
            ),
          );
        }

        return DefaultTabController(
          length: scopes.length,
          child: Column(
            children: [
              Material(
                color: theme.colorScheme.surface,
                elevation: 1,
                child: TabBar(
                  isScrollable: true,
                  tabs: scopes.map((s) => Tab(text: s.name)).toList(),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: scopes.map((scope) {
                    final policies = controller.aiPolicies[scope.id] ?? [];
                    return _buildPolicyList(context, scope, policies);
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildPolicyList(
      BuildContext context, AiScope scope, List<AiPolicy> policies) {
    if (policies.isEmpty) {
      return Center(
        child: Text('لا توجد سياسات مفروضة في نطاق ${scope.name}'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: policies.length,
      itemBuilder: (context, index) {
        final policy = policies[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: _buildActionIcon(policy.action),
            title: Text(policy.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (policy.description != null) Text(policy.description!),
                const SizedBox(height: 4),
                _buildRulesChips(context, policy.rules),
              ],
            ),
            trailing: Chip(
              label: Text('أولوية: ${policy.priority}'),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionIcon(String action) {
    IconData icon;
    Color color;

    switch (action) {
      case 'BLOCK':
        icon = Icons.block;
        color = Colors.red;
        break;
      case 'FORCE_SILENT':
        icon = Icons.notifications_off;
        color = Colors.orange;
        break;
      case 'FORCE_DELIVER':
        icon = Icons.priority_high;
        color = Colors.green;
        break;
      case 'ALLOW_AI':
      default:
        icon = Icons.smart_toy;
        color = Colors.blue;
        break;
    }

    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color),
    );
  }

  Widget _buildRulesChips(BuildContext context, Map<String, dynamic> rules) {
    if (rules.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      children: rules.entries.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${e.key}: ${e.value}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        );
      }).toList(),
    );
  }
}
