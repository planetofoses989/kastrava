import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import 'tab_switcher.dart';

class BottomToolbar extends StatelessWidget {
  final BrowserController controller;
  const BottomToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final count = controller.tabCount;
    return Material(
      color: scheme.surface,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.add, size: 26),
              tooltip: "New tab",
              onPressed: controller.newTab,
            ),
            IconButton(
              tooltip: "Tab switcher",
              onPressed: () => showTabSwitcher(context, controller),
              icon: Badge(
                label: Text('$count'),
                backgroundColor: scheme.primary,
                textColor: scheme.onPrimary,
                child: const Icon(Icons.tab, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
