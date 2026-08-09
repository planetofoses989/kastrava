class DownloadTask {
  int id;
  final String url;
  String fileName;
  String path;
  int received;
  int total;
  int speed;
  String status;
  String error;
  final int createdAt;

  DownloadTask({
    this.id = 0,
    required this.url,
    required this.fileName,
    this.path = "",
    this.received = 0,
    this.total = 0,
    this.speed = 0,
    this.status = "queued",
    this.error = "",
    required this.createdAt,
  });

  double get progress {
    if (total <= 0) return 0;
    return (received / total * 100).clamp(0, 100);
  }

  bool get isActive => status == 'queued' || status == 'downloading';

  bool get isDone => status == 'completed';

  Map<String, dynamic> toMap() => {
        'id': id,
        'url': url,
        'file_name': fileName,
        'path': path,
        'received': received,
        'total': total,
        'speed': speed,
        'status': status,
        'error': error,
        'created_at': createdAt,
      };

  factory DownloadTask.fromMap(Map<String, dynamic> m) => DownloadTask(
        id: m['id'] as int? ?? 0,
        url: m['url'] as String? ?? "",
        fileName: m['file_name'] as String? ?? "",
        path: m['path'] as String? ?? "",
        received: m['received'] as int? ?? 0,
        total: m['total'] as int? ?? 0,
        speed: m['speed'] as int? ?? 0,
        status: m['status'] as String? ?? "queued",
        error: m['error'] as String? ?? "",
        createdAt: m['created_at'] as int? ?? 0,
      );

  DownloadTask copyWith({
    int? id,
    String? fileName,
    String? path,
    int? received,
    int? total,
    int? speed,
    String? status,
    String? error,
  }) =>
      DownloadTask(
        id: id ?? this.id,
        url: url,
        fileName: fileName ?? this.fileName,
        path: path ?? this.path,
        received: received ?? this.received,
        total: total ?? this.total,
        speed: speed ?? this.speed,
        status: status ?? this.status,
        error: error ?? this.error,
        createdAt: createdAt,
      );
}
