import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import '../models/bookmark.dart';
import '../services/app_database.dart';
import '../services/search_service.dart';
import '../services/settings_service.dart';
import 'tab_switcher.dart';

class OmniBar extends StatefulWidget {
  final BrowserController controller;
  const OmniBar({super.key, required this.controller});

  @override
  State<OmniBar> createState() => _OmniBarState();
}

class _OmniBarState extends State<OmniBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  List<String> _suggestions = [];
  bool _suggesting = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      final tab = widget.controller.activeTab;
      final url = tab?.url ?? "";
      if (url.isNotEmpty) {
        _text.text = url;
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: url.length);
      } else {
        _text.clear();
      }
      setState(() {});
    } else {
      _suggesting = false;
      _suggestions = [];
      setState(() {});
    }
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

  Widget _menuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
    );
  }

  void _showMenu(BuildContext context) {
    final tab = widget.controller.activeTab;
    final loading = tab?.loading ?? false;
    final s = SettingsService.instance.settings;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.scheme().surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _menuTile(
                icon: Icons.add,
                title: "New tab",
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.newTab();
                },
              ),
              _menuTile(
                icon: Icons.tab,
                title: "Tab overview",
                onTap: () {
                  Navigator.pop(ctx);
                  showTabSwitcher(context, widget.controller);
                },
              ),
              const Divider(height: 1),
              _menuTile(
                icon: Icons.arrow_forward,
                title: "Forward",
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.goForward();
                },
              ),
              _menuTile(
                icon: loading ? Icons.close : Icons.refresh,
                title: loading ? "Stop" : "Reload",
                onTap: () {
                  Navigator.pop(ctx);
                  if (loading) {
                    widget.controller.stop();
                  } else {
                    widget.controller.reload();
                  }
                },
              ),
              if (s.showHomeBtn)
                _menuTile(
                  icon: Icons.home_outlined,
                  title: "Home",
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.controller.goHome();
                  },
                ),
              if (s.showCopyBtn)
                _menuTile(
                  icon: Icons.content_copy,
                  title: "Copy URL",
                  onTap: () {
                    Navigator.pop(ctx);
                    final url = tab?.url as String? ?? "";
                    if (url.isNotEmpty) _copyToClipboard(context, url);
                  },
                ),
              const Divider(height: 1),
              _menuTile(
                icon: Icons.bookmarks_outlined,
                title: "Bookmark this page",
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleBookmark(context, tab);
                },
              ),
              _menuTile(
                icon: Icons.share,
                title: "Share",
                onTap: () {
                  Navigator.pop(ctx);
                  _share(context, tab);
                },
              ),
              _menuTile(
                icon: Icons.manage_search,
                title: "Find in page",
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.toggleFind();
                },
              ),
              _menuTile(
                icon: Icons.download_outlined,
                title: "Downloads (AnterGet)",
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.toggleDownloads();
                },
              ),
              _menuTile(
                icon: Icons.radar,
                title: "Tracking Radar",
                onTap: () {
                  Navigator.pop(ctx);
                  widget.controller.toggleRadar();
                },
              ),
              _menuTile(
                icon: Icons.settings_outlined,
                title: "Settings",
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
    final scheme = AppTheme.scheme();
    final tab = widget.controller.activeTab;
    final isNew = tab?.isNewTab ?? true;
    final url = tab?.url ?? "";
    final host = tab?.host ?? "";
    final loading = tab?.loading ?? false;
    final focused = _focus.hasFocus;
    final editing = focused || _suggesting;
    final https = url.startsWith('https://');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: "Back",
                onPressed: isNew ? null : widget.controller.goBack,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: editing
                      ? _buildField(scheme, isNew, https)
                      : _buildIdlePill(scheme, isNew, https, host, url,
                          loading),
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: "Menu",
                onPressed: () => _showMenu(context),
              ),
            ],
          ),
        ),
        if (_suggesting && _suggestions.isNotEmpty) _buildSuggestions(context),
      ],
    );
  }

  Widget _buildIdlePill(ColorScheme scheme, bool isNew, bool https,
      String host, String url, bool loading) {
    final display = isNew
        ? "Search or type a URL"
        : (host.isNotEmpty ? host : (url.isNotEmpty ? url : "Search or type a URL"));
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isNew ? Icons.search : (https ? Icons.lock_outline : Icons.public),
                size: 16,
                color: isNew ? scheme.onSurface : scheme.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: scheme.onSurface),
                ),
              ),
            ],
          ),
          if (!isNew && url.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: loading ? widget.controller.stop : widget.controller.reload,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    loading ? Icons.close : Icons.refresh,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildField(ColorScheme scheme, bool isNew, bool https) {
    return Row(
      children: [
        Icon(
          isNew ? Icons.search : (https ? Icons.lock_outline : Icons.public),
          size: 16,
          color: isNew ? scheme.onSurface : scheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            onChanged: _onChanged,
            onSubmitted: _submit,
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
