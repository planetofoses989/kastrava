class Bookmark {
  final int id;
  final String title;
  final String url;
  final String favicon;
  final int createdAt;

  Bookmark({
    this.id = 0,
    required this.title,
    required this.url,
    this.favicon = "",
    required this.createdAt,
  });

  String get host {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'favicon': favicon,
        'created_at': createdAt,
      };

  factory Bookmark.fromMap(Map<String, dynamic> m) => Bookmark(
        id: m['id'] as int? ?? 0,
        title: m['title'] as String? ?? "",
        url: m['url'] as String? ?? "",
        favicon: m['favicon'] as String? ?? "",
        createdAt: m['created_at'] as int? ?? 0,
      );
}
