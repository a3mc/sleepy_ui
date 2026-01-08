import 'package:flutter/material.dart';
import '../../../../core/themes/app_theme.dart';

// Legend widget for circular blade visualization
class CircularBladeLegend extends StatelessWidget {
  const CircularBladeLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RING LEGEND',
              style: theme.textTheme.titleMedium?.copyWith(
                letterSpacing: 1.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),

            // Ring descriptions
            _buildRingDescription(
              'Inner Ring',
              'Vote Distance',
              'Slots behind latest vote',
              theme,
            ),
            const SizedBox(height: 12),

            _buildRingDescription(
              'Middle Ring',
              'Root Distance',
              'Slots behind finalized root',
              theme,
            ),
            const SizedBox(height: 12),

            _buildRingDescription(
              'Outer Ring',
              'Credits Per Cycle',
              'Credits earned per 2s cycle',
              theme,
            ),

            const Divider(height: 32),

            // Color coding
            Text(
              'COLOR CODES',
              style: theme.textTheme.titleMedium?.copyWith(
                letterSpacing: 1.5,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),

            _buildColorLegend(
                AppTheme.healthyColor, 'Healthy', '0 lag / Ahead', theme),
            const SizedBox(height: 8),
            _buildColorLegend(
                AppTheme.warningColor, 'Warning', 'Minor lag', theme),
            const SizedBox(height: 8),
            _buildColorLegend(
                AppTheme.degradedColor, 'Degraded', 'Moderate lag', theme),
            const SizedBox(height: 8),
            _buildColorLegend(
                AppTheme.criticalColor, 'Critical', 'Severe lag', theme),

            const Divider(height: 32),

            // Time window info
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Text(
                  '60-second rolling window',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.refresh, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Text(
                  'Updates every ~1 second',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRingDescription(
    String ringName,
    String metricName,
    String description,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ringName,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.ourValidatorColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          metricName,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white54,
          ),
        ),
      ],
    );
  }

  Widget _buildColorLegend(
      Color color, String status, String meaning, ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                meaning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
