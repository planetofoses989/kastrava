import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import '../models/bookmark.dart';
import '../services/app_database.dart';
import '../services/search_service.dart';
import '../services/settings_service.dart';

class OmniBar extends StatefulWidget {
  final BrowserController controller;
  const OmniBar({super.key, required this.controller});

  @override
  State<OmniBar> createState() => _OmniBarState();
}

class _OmniBarState extends State<OmniBar> {
  final TextEditingController _text = TextEditingController();
  Timer? _debounce;
  List<String> _suggestions = [];
  bool _suggesting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _suggesting = value.trim().isNotEmpty);
    if (value.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final r = await SearchService.instance.fetchSuggestions(value);
      if (!mounted) return;
      setState(() => _suggestions = r);
    });
  }

  void _submit(String input) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _suggestions = [];
      _suggesting = false;
    });
    widget.controller.navigate(input);
  }

  void _useSuggestion(String s) {
    _text.text = s;
    _submit(s);
  }

  void _showMenu(BuildContext context) {
    final tab = widget.controller.activeTab;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.scheme().surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: const Text("Bookmark this page"),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleBookmark(ctx, tab);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text("Share"),
                onTap: () {
                  Navigator.pop(ctx);
                  _share(ctx, tab);
                },
              ),
              ListTile(
                leading: const Icon(Icons.radar),
                title: const Text("Tracking Radar"),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.toggleRadar();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text("Downloads (AnterGet)"),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.toggleDownloads();
                },
              ),
              ListTile(
                leading: const Icon(Icons.manage_search),
                title: const Text("Find in page"),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.toggleFind();
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text("Settings"),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.toggleSettings();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleBookmark(BuildContext ctx, dynamic tab) async {
    final url = tab?.url as String? ?? "";
    if (url.isEmpty) return;
    final db = AppDatabase.instance;
    final exists = await db.isBookmarked(url);
    if (exists) {
      await db.deleteBookmarkByUrl(url);
    } else {
      await db.addBookmark(Bookmark(
        title: (tab?.title as String?)?.isNotEmpty == true
            ? tab!.title
            : tab?.host ?? "Untitled",
        url: url,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(exists ? "Bookmark removed" : "Bookmark added"),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Future<void> _share(BuildContext ctx, dynamic tab) async {
    final url = tab?.url as String? ?? "";
    if (url.isEmpty) return;
    try {
      // Use WebView's share-independent fallback via share sheet is not wired;
      // copy to clipboard as a lightweight substitute.
      await _copyToClipboard(ctx, url);
    } catch (_) {}
  }

  Future<void> _copyToClipboard(BuildContext ctx, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text("Copied to clipboard"),
        duration: Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance.settings;
    final scheme = AppTheme.scheme();
    final tab = widget.controller.activeTab;
    final isNew = tab?.isNewTab ?? true;
    final url = tab?.url ?? "";
    final radius = s.uiRadius == 'large'
        ? 22.0
        : s.uiRadius == 'small'
            ? 6.0
            : 12.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isNew ? Icons.search : Icons.lock_outline,
                        size: 16,
                        color: isNew ? scheme.onSurface : scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          onChanged: _onChanged,
                          onSubmitted: _submit,
                          onTap: () {
                            _text.selection = TextSelection(
                                baseOffset: 0, extentOffset: _text.text.length);
                          },
                          style: TextStyle(fontSize: 15, color: scheme.onSurface),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            filled: false,
                            hintText: "Search or type a URL",
                            contentPadding: EdgeInsets.zero,
                          ),
                          textInputAction: TextInputAction.go,
                        ),
                      ),
                      if (s.showCopyBtn && url.isNotEmpty && !isNew)
                        IconButton(
                          icon: const Icon(Icons.content_copy, size: 16),
                          onPressed: () => _copyToClipboard(context, url),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                    ],
                  ),
                ),
              ),
              if (s.showHomeBtn)
                IconButton(
                  icon: const Icon(Icons.home_outlined),
                  onPressed: widget.controller.goHome,
                ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showMenu(context),
              ),
            ],
          ),
        ),
        if (_suggesting && _suggestions.isNotEmpty) _buildSuggestions(context),
      ],
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    final scheme = AppTheme.scheme();
    final q = _text.text;
    final direct = SearchService.instance.normalizeInput(q);
    final rows = <Widget>[];
    rows.add(_SuggestionTile(
      icon: Icons.search,
      text: "Search \"$q\"",
      onTap: () => _submit(q),
    ));
    if (direct.isNotEmpty) {
      rows.add(_SuggestionTile(
        icon: Icons.north_west,
        text: direct,
        onTap: () => _submit(direct),
      ));
    }
    for (final sug in _suggestions) {
      rows.add(_SuggestionTile(
        icon: Icons.north_west,
        text: sug,
        onTap: () => _useSuggestion(sug),
      ));
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
      ),
      child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: rows),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _SuggestionTile({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18, color: scheme.onSurface),
      title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
