import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import '../services/settings_service.dart';
import '../widgets/top_sites.dart';

class NewTabPage extends StatefulWidget {
  final BrowserController controller;
  final VoidCallback? onFocusSearch;
  const NewTabPage({
    super.key,
    required this.controller,
    this.onFocusSearch,
  });

  @override
  State<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends State<NewTabPage> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final s = SettingsService.instance.settings;
    final hour = _now.hour;

    String greeting;
    if (hour < 12) {
      greeting = "Good morning";
    } else if (hour < 17) {
      greeting = "Good afternoon";
    } else {
      greeting = "Good evening";
    }

    final timeStr = _time(_now);
    final dateStr = _date(_now);

    return Container(
      color: scheme.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: constraints.maxHeight * 0.06),
                  if (s.showNtpClock) ...[
                    Text(
                      timeStr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                        height: 1.1,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      greeting,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  if (s.showNtpLogo)
                    Center(
                      child: Image.asset(
                        'assets/logo.png',
                        width: 88,
                        height: 88,
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: widget.onFocusSearch,
                    child: Container(
                      height: 50,
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            size: 20,
                            color: scheme.onSurface.withValues(alpha: .55),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "Search or type URL",
                            style: TextStyle(
                              fontSize: 15,
                              color: scheme.onSurface.withValues(alpha: .6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TopSitesGrid(controller: widget.controller),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _time(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  String _date(DateTime d) {
    const months = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December",
    ];
    const days = [
      "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ];
    final weekday = days[d.weekday - 1];
    final month = months[d.month - 1];
    return "$weekday, $month ${d.day}";
  }
}
