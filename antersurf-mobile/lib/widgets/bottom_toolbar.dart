import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';

class BottomToolbar extends StatelessWidget {
  final BrowserController controller;
  const BottomToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final tab = controller.activeTab;

    Widget navBtn(IconData icon, VoidCallback onTap) {
      return IconButton(icon: Icon(icon), onPressed: onTap);
    }

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
            navBtn(Icons.arrow_back, tab != null && !tab.isNewTab
                ? controller.goBack
                : () {}),
            navBtn(Icons.arrow_forward, controller.goForward),
            IconButton(
              icon: tab != null && tab.loading
                  ? const Icon(Icons.close)
                  : const Icon(Icons.refresh),
              onPressed: tab != null && tab.loading
                  ? controller.stop
                  : controller.reload,
            ),
            IconButton(
              icon: const Icon(Icons.home_outlined),
              onPressed: controller.goHome,
            ),
            navBtn(Icons.shield_outlined, controller.toggleRadar),
            navBtn(Icons.tab, controller.newTab),
            Builder(builder: (ctx) {
              return IconButton(
                icon: const Icon(Icons.apps),
                onPressed: () => controller.toggleSidePanel(),
                color: controller.sidePanelVisible ? scheme.primary : null,
              );
            }),
          ],
        ),
      ),
    );
  }
}
