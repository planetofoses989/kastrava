class BrowserTab {
  final int id;
  String title;
  String url;
  bool loading;
  bool canGoBack;
  bool canGoForward;
  bool pinned;
  bool muted;
  bool isNewTab;
  double progress;

  BrowserTab({
    required this.id,
    this.title = "New Tab",
    this.url = "",
    this.loading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.pinned = false,
    this.muted = false,
    this.isNewTab = true,
    this.progress = 0,
  });

  String get host {
    if (url.isEmpty) return "";
    try {
      final uri = Uri.parse(url);
      return uri.host.isEmpty ? url : uri.host;
    } catch (_) {
      return url;
    }
  }

  String get displayUrl {
    if (url.isEmpty) return "";
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.host;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'pinned': pinned,
        'muted': muted,
        'isNewTab': isNewTab,
      };

  factory BrowserTab.fromJson(Map<String, dynamic> m) => BrowserTab(
        id: m['id'] as int? ?? 0,
        title: m['title'] as String? ?? "New Tab",
        url: m['url'] as String? ?? "",
        pinned: m['pinned'] as bool? ?? false,
        muted: m['muted'] as bool? ?? false,
        isNewTab: m['isNewTab'] as bool? ?? true,
      );
}
