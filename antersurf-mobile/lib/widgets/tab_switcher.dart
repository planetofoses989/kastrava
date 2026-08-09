import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';

Future<void> showTabSwitcher(
    BuildContext context, BrowserController controller) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.scheme().surface,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final scheme = AppTheme.scheme();
          final tabs = controller.allTabs;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Text(
                          "Tabs",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            controller.newTab();
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text("New tab"),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: tabs.isEmpty
                        ? Center(
                            child: Text(
                              "No tabs",
                              style: TextStyle(color: scheme.onSurface),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: tabs.length,
                            itemBuilder: (context, i) {
                              final t = tabs[i];
                              final active = t.id == controller.activeId;
                              final title = t.title.isNotEmpty
                                  ? t.title
                                  : (t.host.isNotEmpty ? t.host : "New Tab");
                              return GestureDetector(
                                onTap: () {
                                  controller.activateTab(t.id);
                                  Navigator.pop(ctx);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: active
                                          ? scheme.primary
                                          : scheme.outlineVariant,
                                      width: active ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          margin: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerLow,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: t.host.isNotEmpty
                                              ? Center(
                                                  child: Icon(
                                                    Icons.language,
                                                    color: scheme.onSurface
                                                        .withValues(alpha: .5),
                                                  ),
                                                )
                                              : const SizedBox(),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 2, 6, 8),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: scheme.onSurface,
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () {
                                                controller.closeTab(t.id);
                                                setSheetState(() {});
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(4),
                                                child: Icon(
                                                  Icons.close,
                                                  size: 14,
                                                  color: scheme.onSurface,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
