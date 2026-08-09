import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import '../models/bookmark.dart';
import '../models/history_entry.dart';
import '../services/app_database.dart';

class SidePanelScreen extends StatefulWidget {
  final BrowserController controller;
  const SidePanelScreen({super.key, required this.controller});

  @override
  State<SidePanelScreen> createState() => _SidePanelScreenState();
}

class _SidePanelScreenState extends State<SidePanelScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return Positioned.fill(
      child: Material(
        color: scheme.background,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.controller.toggleSidePanel,
                  ),
                  Expanded(
                    child: SegmentedButton<int>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(value: 0, label: Text("Bookmarks"), icon: Icon(Icons.bookmarks, size: 16)),
                        ButtonSegment(value: 1, label: Text("History"), icon: Icon(Icons.history, size: 16)),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (v) => setState(() => _tab = v.first),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_tab) {
                0 => _BookmarksList(controller: widget.controller),
                _ => _HistoryList(controller: widget.controller),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarksList extends StatefulWidget {
  final BrowserController controller;
  const _BookmarksList({required this.controller});

  @override
  State<_BookmarksList> createState() => _BookmarksListState();
}

class _BookmarksListState extends State<_BookmarksList> {
  List<Bookmark> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await AppDatabase.instance.getBookmarks();
    if (!mounted) return;
    setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    if (_items.isEmpty) {
      return Center(
        child: Text("No bookmarks",
            style: TextStyle(color: scheme.onSurface)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final b = _items[i];
        return ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: scheme.primary.withValues(alpha: .2),
            child: Text(
              b.title.isEmpty ? "?" : b.title[0].toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(b.title.isEmpty ? b.url : b.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(b.url,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () {
            widget.controller.navigate(b.url);
            widget.controller.toggleSidePanel();
          },
          onLongPress: () async {
            await AppDatabase.instance.deleteBookmark(b.id);
            _load();
          },
        );
      },
    );
  }
}

class _HistoryList extends StatefulWidget {
  final BrowserController controller;
  const _HistoryList({required this.controller});

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  List<HistoryEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await AppDatabase.instance.getHistory();
    if (!mounted) return;
    setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return Column(
      children: [
        if (_items.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () async {
                  await AppDatabase.instance.clearHistory();
                  _load();
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text("Clear"),
              ),
            ),
          ),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Text("No history",
                      style: TextStyle(color: scheme.onSurface)))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final h = _items[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.history, size: 18),
                      title: Text(h.title.isEmpty ? h.url : h.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(h.url,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text(
                        _relTime(h.visitedAt),
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurface),
                      ),
                      onTap: () {
                        widget.controller.navigate(h.url);
                        widget.controller.toggleSidePanel();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _relTime(int ms) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return "now";
    if (diff.inHours < 1) return "${diff.inMinutes}m ago";
    if (diff.inDays < 1) return "${diff.inHours}h ago";
    if (diff.inDays < 7) return "${diff.inDays}d ago";
    return "${(diff.inDays / 7).floor()}w ago";
  }
}
