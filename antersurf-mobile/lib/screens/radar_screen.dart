import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';

class RadarScreen extends StatelessWidget {
  final BrowserController controller;
  const RadarScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final stats = controller.radarStats();
    final events = controller.radarEvents;

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      width: 320,
      child: Material(
        color: scheme.surface,
        elevation: 8,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(
                    "Tracking Radar",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: controller.clearRadar,
                    tooltip: "Reset",
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: controller.toggleRadar,
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    "${stats['score']}",
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: _scoreColor(scheme, stats['score'] as int),
                    ),
                  ),
                  Text(
                    "privacy score",
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Metric(
                        label: "requests",
                        value: "${stats['reqs']}",
                        color: scheme.onSurface,
                      ),
                      _Metric(
                        label: "third-party",
                        value: "${stats['third']}",
                        color: scheme.onSurface,
                      ),
                      _Metric(
                        label: "host",
                        value: stats['mainHost'] == ""
                            ? "—"
                            : stats['mainHost'] as String,
                        color: scheme.onSurface,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: events.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 40, color: scheme.onSurface),
                          const SizedBox(height: 8),
                          Text(
                            "No requests detected yet",
                            style: TextStyle(color: scheme.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Browse a page to see network activity",
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurface),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: events.length,
                      itemBuilder: (context, i) {
                        final e = events[i];
                        final third = e['third'] == true;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            third
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            size: 18,
                            color: third
                                ? scheme.error
                                : scheme.primary,
                          ),
                          title: Text(
                            e['host'] as String? ?? "unknown",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurface),
                          ),
                          subtitle: Text(
                            "${third ? 'third-party' : 'first-party'} · ${e['kind']}",
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurface),
                          ),
                          trailing: Text(
                            _ts(e['ts'] as int? ?? 0),
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurface),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(ColorScheme scheme, int score) {
    if (score >= 90) return const Color(0xFF4CAF50);
    if (score >= 60) return const Color(0xFFFF9800);
    return scheme.error;
  }

  String _ts(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    final s = d.second.toString().padLeft(2, '0');
    return "$h:$m:$s";
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}
