import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';

class TabStrip extends StatelessWidget {
  final BrowserController controller;
  final ScrollController scroll;
  const TabStrip({super.key, required this.controller, required this.scroll});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final tabs = controller.allTabs;
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: 44,
        child: Scrollbar(
          controller: scroll,
          thumbVisibility: false,
          child: ListView.builder(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: tabs.length,
            itemBuilder: (context, i) {
              final t = tabs[i];
              final active = t.id == controller.activeId;
              return _TabChip(
                tab: t,
                active: active,
                onTap: () => controller.activateTab(t.id),
                onClose: () => controller.closeTab(t.id),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final dynamic tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _TabChip({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final title = tab.title as String? ?? "New Tab";
    final host = (tab.host as String?) ?? "";
    final isNew = tab.isNewTab as bool? ?? true;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        width: 168,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? scheme.surfaceContainerHighest : scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? scheme.primary.withValues(alpha: .6) : scheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            if (!isNew)
              _Favicon(host: host, initial: title.isNotEmpty ? title[0] : "?")
            else
              Icon(Icons.search, size: 14, color: scheme.onSurface),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isNew ? "New Tab" : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface,
                ),
              ),
            ),
            InkWell(
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 12, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Favicon extends StatelessWidget {
  final String host;
  final String initial;
  const _Favicon({required this.host, required this.initial});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(fontSize: 8, color: scheme.onSurface),
      ),
    );
  }
}
