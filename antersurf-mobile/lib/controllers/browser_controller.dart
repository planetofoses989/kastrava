import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/browser_tab.dart';
import '../services/anterget_service.dart';
import '../services/app_database.dart';
import '../services/search_service.dart';
import '../services/settings_service.dart';
import '../models/history_entry.dart';

class BrowserController extends ChangeNotifier {
  final List<BrowserTab> tabs = [];
  int _nextId = 1;
  int _activeId = 0;

  final Map<int, InAppWebViewController> _controllers = {};

  bool radarVisible = false;
  bool findVisible = false;
  bool settingsVisible = false;
  bool sidePanelVisible = false;
  bool downloadsVisible = false;

  String findQuery = "";
  int findMatches = 0;

  // Tracking radar live events
  final List<Map<String, dynamic>> radarEvents = [];

  BrowserTab? get activeTab {
    for (final t in tabs) {
      if (t.id == _activeId) return t;
    }
    return tabs.isEmpty ? null : tabs.first;
  }

  InAppWebViewController? get activeController => _controllers[_activeId];

  int get activeId => _activeId;

  int get tabCount => tabs.length;

  List<BrowserTab> get allTabs => List.unmodifiable(tabs);

  int get activeIndexInList {
    final idx = tabs.indexWhere((t) => t.id == _activeId);
    return idx < 0 ? 0 : idx;
  }

  BrowserTab? _tabById(int id) {
    for (final t in tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> restore() async {
    final s = SettingsService.instance.settings;
    if (s.startup == 'home' && s.homepage.isNotEmpty) {
      _addNewTab(loadUrl: s.homepage);
      return;
    }
    if (s.startup == 'last') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('antersurf.session');
        if (raw != null && raw.isNotEmpty) {
          final urls = (raw.split('\n'))
              .where((u) => u.isNotEmpty && !u.startsWith('about:') && !u.startsWith('data:'))
              .toList();
          if (urls.isNotEmpty) {
            for (final u in urls) {
              _addNewTab(loadUrl: u);
            }
            return;
          }
        }
      } catch (_) {}
    }
    _addNewTab();
  }

  Future<void> saveSession() async {
    try {
      final urls = tabs
          .map((t) => t.url)
          .where((u) => u.isNotEmpty)
          .toSet()
          .join('\n');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('antersurf.session', urls);
    } catch (_) {}
  }

  Future<void> newTab({String? url}) async {
    _addNewTab(loadUrl: url);
  }

  void _addNewTab({String? loadUrl}) {
    final id = _nextId++;
    final tab = BrowserTab(id: id);
    tabs.add(tab);
    _activeId = id;

    if (loadUrl != null && loadUrl.isNotEmpty) {
      final url = SearchService.instance.toSearchUrl(loadUrl);
      tab.url = url;
      tab.isNewTab = false;
      tab.loading = true;
      _recordHistory(tab, url);
    }
    notifyListeners();
  }

  void registerWebView(int tabId, InAppWebViewController c) {
    _controllers[tabId] = c;
  }

  void onProgress(int tabId, int progress) {
    final tab = _tabById(tabId);
    if (tab == null) return;
    tab.progress = progress / 100;
    tab.loading = progress < 100;
    notifyListeners();
  }

  void onPageStarted(int tabId, String url) {
    final tab = _tabById(tabId);
    if (tab == null) return;
    tab.loading = true;
    tab.url = url;
    tab.isNewTab = false;
    _radarEvent(url);
    notifyListeners();
  }

  void onPageFinished(int tabId, String url) {
    final tab = _tabById(tabId);
    if (tab == null) return;
    tab.loading = false;
    tab.isNewTab = false;
    _captureTitle(tab);
    notifyListeners();
  }

  void onTitle(int tabId, String? title) {
    final tab = _tabById(tabId);
    if (tab == null || title == null || title.isEmpty) return;
    tab.title = title;
    notifyListeners();
  }

  void onUrlChanged(int tabId, String url) {
    final tab = _tabById(tabId);
    if (tab == null) return;
    if (url.isNotEmpty && url != tab.url) {
      tab.url = url;
      notifyListeners();
    }
  }

  void onWebResourceError(int tabId) {
    final tab = _tabById(tabId);
    if (tab == null) return;
    tab.loading = false;
    tab.title = "Page failed to load";
    notifyListeners();
  }

  Future<NavigationActionPolicy?> onDownloadStart(
      int tabId, DownloadStartRequest request) async {
    var name = (request.suggestedFilename ?? '').trim();
    if (name.isEmpty) {
      name = _fileNameFromContentDisposition(request.contentDisposition) ?? '';
    }
    final url = request.url.toString();
    if (url.isNotEmpty) {
      await AnterGetService.instance.start(url,
          suggestedName: name.isEmpty ? null : name);
    }
    return null;
  }

  static String? _fileNameFromContentDisposition(String? cd) {
    if (cd == null || cd.isEmpty) return null;
    final star =
        RegExp(r"filename\*\s*=\s*UTF-8''([^;]+)").firstMatch(cd);
    if (star != null) {
      try {
        return Uri.decodeComponent(star.group(1)!.trim());
      } catch (_) {}
    }
    final m = RegExp(r'filename="?([^";]+)"?').firstMatch(cd);
    if (m != null) return m.group(1)!.trim();
    return null;
  }

  Future<void> _captureTitle(BrowserTab tab) async {
    try {
      final c = _controllers[tab.id];
      if (c == null) return;
      final title = await c.getTitle();
      if (title != null && title.isNotEmpty) {
        tab.title = title;
        notifyListeners();
      }
    } catch (_) {}
  }

  void activateTab(int id) {
    if (id == _activeId) return;
    _activeId = id;
    notifyListeners();
  }

  Future<void> closeTab(int id) async {
    if (tabs.length == 1) return;
    final idx = tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final c = _controllers.remove(id);
    try {
      if (c != null) await c.clearCache();
    } catch (_) {}
    tabs.removeAt(idx);
    if (_activeId == id) {
      _activeId = tabs[idx.clamp(0, tabs.length - 1)].id;
    }
    notifyListeners();
  }

  Future<void> closeAllTabs() async {
    for (final c in _controllers.values) {
      try {
        await c.clearCache();
      } catch (_) {}
    }
    _controllers.clear();
    tabs.clear();
    _addNewTab();
  }

  Future<void> goBack() async {
    final c = activeController;
    if (c == null) return;
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> goForward() async {
    final c = activeController;
    if (c == null) return;
    try {
      if (await c.canGoForward()) {
        await c.goForward();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> reload() async {
    final c = activeController;
    if (c == null) return;
    try {
      await c.reload();
    } catch (_) {}
  }

  Future<void> stop() async {
    final c = activeController;
    if (c == null) return;
    try {
      await c.evaluateJavascript(source: 'window.stop();');
    } catch (_) {}
  }

  Future<void> navigate(String input) async {
    final t = activeTab;
    if (t == null) return;
    final url = SearchService.instance.toSearchUrl(input);
    t.url = url;
    t.isNewTab = false;
    t.loading = true;
    notifyListeners();
    final c = activeController;
    if (c != null) {
      try {
        await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      } catch (_) {
        t.loading = false;
        notifyListeners();
      }
    }
    _recordHistory(t, url);
  }

  void goHome() {
    final s = SettingsService.instance.settings;
    if (s.homepage.isNotEmpty) {
      navigate(s.homepage);
    } else {
      showNewTab();
    }
  }

  Future<void> showNewTab() async {
    final t = activeTab;
    if (t == null) return;
    t.url = "";
    t.title = "New Tab";
    t.isNewTab = true;
    t.loading = false;
    notifyListeners();
  }

  Future<void> _recordHistory(BrowserTab tab, String url) async {
    final s = SettingsService.instance.settings;
    if (s.tracking == 'off' && s.dnt == 'on') return;
    await AppDatabase.instance.addHistory(HistoryEntry(
      title: tab.title,
      url: url,
      visitedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _radarEvent(String url) {
    final t = activeTab;
    if (t == null) return;
    if (t.isNewTab) return;
    final host = Uri.tryParse(url)?.host ?? '';
    final mainHost = t.host;
    final third = host.isNotEmpty && mainHost.isNotEmpty && host != mainHost;
    radarEvents.insert(0, {
      'host': host,
      'third': third,
      'kind': 'main',
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    if (radarEvents.length > 300) radarEvents.removeLast();
    if (radarVisible) notifyListeners();
  }

  Map<String, dynamic> radarStats() {
    final mainHost = activeTab?.host ?? "";
    int reqs = 0, third = 0;
    for (final e in radarEvents) {
      reqs++;
      if (e['third'] == true) third++;
    }
    final score = (100 - reqs * 0.4 - third * 1.5).clamp(0, 100).round();
    return {'mainHost': mainHost, 'reqs': reqs, 'third': third, 'score': score};
  }

  void clearRadar() {
    radarEvents.clear();
    notifyListeners();
  }

  void toggleRadar() {
    radarVisible = !radarVisible;
    notifyListeners();
  }

  void toggleFind() {
    findVisible = !findVisible;
    notifyListeners();
  }

  Future<void> findNext(String q) async {
    findQuery = q;
    findMatches = 0;
    final c = activeController;
    if (c == null) return;
    final js = _esc(q);
    try {
      final result = await c.evaluateJavascript(source: '''
        (function(){
          var found = window.find("$js", false, false, true);
          return found;
        })();
      ''');
      findMatches = int.tryParse('$result') ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  void toggleSettings() {
    settingsVisible = !settingsVisible;
    notifyListeners();
  }

  void toggleSidePanel() {
    sidePanelVisible = !sidePanelVisible;
    notifyListeners();
  }

  void toggleDownloads() {
    downloadsVisible = !downloadsVisible;
    notifyListeners();
  }

  Future<int> enqueueDownload(String url, {String? suggestedName}) {
    return AnterGetService.instance.start(url,
        suggestedName: suggestedName);
  }

  static String _esc(String s) =>
      s.replaceAll("\\", "\\\\").replaceAll("'", "\\'");

  @override
  void dispose() {
    for (final c in _controllers.values) {
      try {
        c.clearCache();
      } catch (_) {}
    }
    super.dispose();
  }
}
