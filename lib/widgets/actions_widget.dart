import 'package:flutter/material.dart';
import '../models/meeting_model.dart';

class ActionsWidget extends StatelessWidget {
  final List<ActionItem> actionItems;

  const ActionsWidget({super.key, required this.actionItems});

  @override
  Widget build(BuildContext context) {
    if (actionItems.isEmpty) {
      return const SizedBox.shrink();
    }

    // Returning a Column instead of ListView fixes the nested Viewport crash,
    // since the parent page is already scrollable.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: actionItems.map((item) {
        final cs = Theme.of(context).colorScheme;
        return Card(
          elevation: 0,
          color: cs.surfaceContainerHighest.withOpacity(0.4),
          margin: const EdgeInsets.only(bottom: 12.0),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.task_alt, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.task,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildPill(
                            context,
                            icon: Icons.person_outline,
                            text: item.assignee,
                            color: cs.secondary,
                            bgColor: cs.secondaryContainer,
                          ),
                          if (item.deadline.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _buildPill(
                              context,
                              icon: Icons.calendar_today,
                              text: item.deadline,
                              color: cs.error,
                              bgColor: cs.errorContainer,
                            ),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPill(BuildContext context,
      {required IconData icon,
      required String text,
      required Color color,
      required Color bgColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
