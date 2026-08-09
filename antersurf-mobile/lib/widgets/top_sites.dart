import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import '../models/bookmark.dart';
import '../services/app_database.dart';
import '../services/search_service.dart';
import '../services/settings_service.dart';

class TopSitesGrid extends StatefulWidget {
  final BrowserController controller;
  const TopSitesGrid({super.key, required this.controller});

  @override
  State<TopSitesGrid> createState() => _TopSitesGridState();
}

class _TopSitesGridState extends State<TopSitesGrid> {
  List<Bookmark> _sites = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bookmarks = await AppDatabase.instance.getBookmarks();
    if (!mounted) return;
    setState(() {
      _sites = bookmarks.take(12).toList();
      _loaded = true;
    });
  }

  Future<void> _addShortcut() async {
    final scheme = AppTheme.scheme();
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: "https://");
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface,
        title: const Text("Add shortcut"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: "URL"),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Save")),
        ],
      ),
    );
    if (result == true) {
      final title = titleCtrl.text.trim().isEmpty ? "Shortcut" : titleCtrl.text.trim();
      final url = urlCtrl.text.trim();
      if (url.isNotEmpty) {
        await AppDatabase.instance.addBookmark(Bookmark(
          title: title,
          url: url,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _load();
      }
    }
  }

  Future<void> _remove(Bookmark b) async {
    await AppDatabase.instance.deleteBookmark(b.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final s = SettingsService.instance.settings;
    final cols = s.speedDial == 'compact' ? 5 : 4;

    if (!_loaded) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 8,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: _sites.length + 1,
      itemBuilder: (context, i) {
        if (i == _sites.length) {
          return _SiteTile(
            icon: Icons.add,
            label: "Add shortcut",
            color: scheme.surfaceContainerHighest,
            onTap: _addShortcut,
          );
        }
        final b = _sites[i];
        return _SiteTile(
          icon: Icons.public,
          label: b.title.isEmpty ? b.host : b.title,
          color: _color(b.url),
          initial: SearchService.instance.initialFor(b.title),
          onTap: () => widget.controller.navigate(b.url),
          onLongPress: () => _remove(b),
        );
      },
    );
  }

  Color _color(String url) {
    final seed = url.hashCode.abs();
    final hue = seed % 360;
    return HSLColor.fromAHSL(0.85, hue.toDouble(), 0.5, 0.45).toColor();
  }
}

class _SiteTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String initial;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SiteTile({
    required this.icon,
    required this.label,
    required this.color,
    this.initial = "",
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: initial.isNotEmpty
                  ? Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, size: 16, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
