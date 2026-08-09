class HistoryEntry {
  final int id;
  final String title;
  final String url;
  final String favicon;
  final int visitedAt;

  HistoryEntry({
    this.id = 0,
    required this.title,
    required this.url,
    this.favicon = "",
    required this.visitedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'url': url,
        'favicon': favicon,
        'visited_at': visitedAt,
      };

  factory HistoryEntry.fromMap(Map<String, dynamic> m) => HistoryEntry(
        id: m['id'] as int? ?? 0,
        title: m['title'] as String? ?? "",
        url: m['url'] as String? ?? "",
        favicon: m['favicon'] as String? ?? "",
        visitedAt: m['visited_at'] as int? ?? 0,
      );
}
