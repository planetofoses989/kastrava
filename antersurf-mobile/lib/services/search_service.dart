import 'dart:convert';

import 'package:http/http.dart' as http;

import 'settings_service.dart';

class SearchService {
  static final SearchService instance = SearchService._();
  SearchService._();

  String normalizeInput(String input) {
    final t = input.trim();
    if (t.isEmpty) return "";
    if (t.startsWith('about:')) return t;
    if (t.startsWith('file:')) return t;
    if (t.contains(' ')) return "";
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return t;
    if (RegExp(r'^[\w-]+(\.[\w-]+)+([/\?#][\s\S]*)?$').hasMatch(t)) {
      return t.contains('.') ? 'https://$t' : "";
    }
    if (t.contains('.') && !t.contains(' ')) return 'https://$t';
    return "";
  }

  String toSearchUrl(String input) {
    final url = normalizeInput(input);
    if (url.isNotEmpty) return url;
    return SettingsService.instance.settings.searchUrl + Uri.encodeComponent(input.trim());
  }

  Future<List<String>> fetchSuggestions(String query) async {
    final s = SettingsService.instance.settings;
    if (query.trim().isEmpty || s.suggest != 'on') return [];
    final base = s.suggestionUrl;
    if (base.isEmpty) return [];
    try {
      final uri = Uri.parse(base + Uri.encodeComponent(query));
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return [];
      final ct = res.headers['content-type'] ?? '';
      dynamic decoded;
      if (ct.contains('json')) {
        decoded = jsonDecode(res.body);
      } else {
        decoded = jsonDecode(res.body); // most engines return JSON despite header
      }
      if (decoded is List && decoded.isNotEmpty && decoded[1] is List) {
        return (decoded[1] as List).take(12).map((e) => '$e').toList();
      }
      if (decoded is List) {
        return decoded.take(12).map((e) => '$e').toList();
      }
    } catch (_) {}
    return [];
  }

  String faviconFor(String url) {
    try {
      final u = Uri.parse(url);
      return "https://${u.host}/favicon.ico";
    } catch (_) {
      return "";
    }
  }

  String initialFor(String title) {
    if (title.isEmpty) return "?";
    return title.substring(0, 1).toUpperCase();
  }

  String colorFor(String seed) {
    final h = seed.hashCode.abs() % 360;
    final s = 55 + seed.hashCode.abs() % 25;
    final l = 45 + seed.hashCode.abs() % 15;
    return "hsl($h,$s%,$l%)";
  }
}
