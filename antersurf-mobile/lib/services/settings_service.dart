import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  String searchEngine;
  String customEngine;
  String accent;
  String theme;
  String homepage;
  String startup;
  String confirmClose;
  String bookmarkBar;
  String suggest;
  String fontSize;
  String reduceAnimations;
  String dnt;
  String tracking;
  String cookies;
  String location;
  String zoom;
  String uiRadius;
  String speedDial;
  bool showHomeBtn;
  bool showCopyBtn;
  bool showNtpClock;
  bool showNtpLogo;
  int maxSuggestions;
  bool sendReferrer;
  bool showProgressBar;
  int downloadsParallel;

  AppSettings({
    this.searchEngine = 'duckduckgo',
    this.customEngine = '',
    this.accent = '#8ab4f8',
    this.theme = 'dark',
    this.homepage = '',
    this.startup = 'last',
    this.confirmClose = 'off',
    this.bookmarkBar = 'auto',
    this.suggest = 'on',
    this.fontSize = '12',
    this.reduceAnimations = 'off',
    this.dnt = 'on',
    this.tracking = 'standard',
    this.cookies = 'off',
    this.location = 'block',
    this.zoom = '100',
    this.uiRadius = 'medium',
    this.speedDial = 'comfortable',
    this.showHomeBtn = false,
    this.showCopyBtn = true,
    this.showNtpClock = true,
    this.showNtpLogo = true,
    this.maxSuggestions = 8,
    this.sendReferrer = false,
    this.showProgressBar = true,
    this.downloadsParallel = 2,
  });

  String get searchUrl {
    final q = "https://duckduckgo.com/?q=";
    switch (searchEngine) {
      case 'google':
        return "https://www.google.com/search?q=";
      case 'bing':
        return "https://www.bing.com/search?q=";
      case 'brave':
        return "https://search.brave.com/search?q=";
      case 'yahoo':
        return "https://search.yahoo.com/search?p=";
      case 'ecosia':
        return "https://www.ecosia.org/search?q=";
      case 'custom':
        return customEngine.isEmpty ? q : customEngine;
      default:
        return q;
    }
  }

  String get suggestionUrl {
    switch (searchEngine) {
      case 'google':
        return "https://suggestqueries.google.com/complete/search?client=firefox&q=";
      case 'bing':
        return "https://api.bing.com/osjson.aspx?query=";
      case 'brave':
        return "https://search.brave.com/api/suggest?q=";
      case 'yahoo':
        return "https://search.yahoo.com/sugg/gossip-us-sb/gossip-in-srch.json?output=fxjson&command=";
      case 'ecosia':
        return "https://ac.ecosia.org/?q=";
      case 'custom':
        return "";
      default:
        return "https://duckduckgo.com/ac/?q=";
    }
  }

  double get accentColor => _hexToDouble(accent);

  double get textZoom => (double.tryParse(fontSize) ?? 12) / 12;

  bool get reduceMotion => reduceAnimations == 'on';

  static double _hexToDouble(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 3) {
      h = h.split('').map((c) => c * 2).join();
    }
    final v = int.tryParse(h.length >= 6 ? h.substring(0, 6) : h, radix: 16) ?? 0;
    return v / 0xFFFFFF;
  }
}

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  late AppSettings settings;
  static const _key = "antersurf.settings.v1";

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      settings = AppSettings();
    } else {
      try {
        final m = Map<String, dynamic>.from(Uri.splitQueryString(raw));
        settings = _fromMap(m);
      } catch (_) {
        settings = AppSettings();
      }
    }
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final parts = <String>[];
    final m = _toMap(settings);
    m.forEach((k, v) => parts.add("$k=${Uri.encodeQueryComponent('$v')}"));
    await prefs.setString(_key, parts.join("&"));
  }

  Future<void> set(String key, dynamic value) async {
    final m = _toMap(settings);
    m[key] = value;
    settings = _fromMap(m);
    notifyListeners();
    await save();
  }

  Map<String, dynamic> _toMap(AppSettings s) => {
        'searchEngine': s.searchEngine,
        'customEngine': s.customEngine,
        'accent': s.accent,
        'theme': s.theme,
        'homepage': s.homepage,
        'startup': s.startup,
        'confirmClose': s.confirmClose,
        'bookmarkBar': s.bookmarkBar,
        'suggest': s.suggest,
        'fontSize': s.fontSize,
        'reduceAnimations': s.reduceAnimations,
        'dnt': s.dnt,
        'tracking': s.tracking,
        'cookies': s.cookies,
        'location': s.location,
        'zoom': s.zoom,
        'uiRadius': s.uiRadius,
        'speedDial': s.speedDial,
        'showHomeBtn': s.showHomeBtn,
        'showCopyBtn': s.showCopyBtn,
        'showNtpClock': s.showNtpClock,
        'showNtpLogo': s.showNtpLogo,
        'maxSuggestions': s.maxSuggestions,
        'sendReferrer': s.sendReferrer,
        'showProgressBar': s.showProgressBar,
        'downloadsParallel': s.downloadsParallel,
      };

  AppSettings _fromMap(Map<String, dynamic> m) {
    AppSettings base() => AppSettings();
    return AppSettings(
      searchEngine: m['searchEngine'] as String? ?? base().searchEngine,
      customEngine: m['customEngine'] as String? ?? base().customEngine,
      accent: m['accent'] as String? ?? base().accent,
      theme: m['theme'] as String? ?? base().theme,
      homepage: m['homepage'] as String? ?? base().homepage,
      startup: m['startup'] as String? ?? base().startup,
      confirmClose: m['confirmClose'] as String? ?? base().confirmClose,
      bookmarkBar: m['bookmarkBar'] as String? ?? base().bookmarkBar,
      suggest: m['suggest'] as String? ?? base().suggest,
      fontSize: m['fontSize'] as String? ?? base().fontSize,
      reduceAnimations: m['reduceAnimations'] as String? ?? base().reduceAnimations,
      dnt: m['dnt'] as String? ?? base().dnt,
      tracking: m['tracking'] as String? ?? base().tracking,
      cookies: m['cookies'] as String? ?? base().cookies,
      location: m['location'] as String? ?? base().location,
      zoom: m['zoom'] as String? ?? base().zoom,
      uiRadius: m['uiRadius'] as String? ?? base().uiRadius,
      speedDial: m['speedDial'] as String? ?? base().speedDial,
      showHomeBtn: m['showHomeBtn'] as bool? ?? base().showHomeBtn,
      showCopyBtn: m['showCopyBtn'] as bool? ?? base().showCopyBtn,
      showNtpClock: m['showNtpClock'] as bool? ?? base().showNtpClock,
      showNtpLogo: m['showNtpLogo'] as bool? ?? base().showNtpLogo,
      maxSuggestions: int.tryParse('${m['maxSuggestions']}') ?? base().maxSuggestions,
      sendReferrer: m['sendReferrer'] as bool? ?? base().sendReferrer,
      showProgressBar: m['showProgressBar'] as bool? ?? base().showProgressBar,
      downloadsParallel: int.tryParse('${m['downloadsParallel']}') ?? base().downloadsParallel,
    );
  }
}
