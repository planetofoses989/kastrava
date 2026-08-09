import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_curl/flutter_curl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/download_task.dart';
import 'app_database.dart';
import 'settings_service.dart';

/// AnterGet — the curl-based download engine for AnterSurf Mobile.
///
/// Every byte is transferred by libcurl (via `flutter_curl`). Downloads are
/// memory-bounded by fetching the file in 1 MiB ranged chunks, which also
/// gives us resumable pauses (HTTP Range), live progress, speed and ETA —
/// mirroring the desktop AnterGet engine which drives the `curl` CLI.
class AnterGetService extends ChangeNotifier {
  static final AnterGetService instance = AnterGetService._();
  AnterGetService._();

  static const int chunkSize = 1024 * 1024;
  static const int maxRedirects = 10;

  Client? _client;
  bool _initDone = false;

  /// Newest task first.
  final List<DownloadTask> tasks = [];

  final Set<int> _active = {};
  final Set<int> _pauseRequested = {};
  final Set<int> _cancelRequested = {};
  final Set<int> _removePending = {};
  final Map<int, RandomAccessFile> _handles = {};
  final Map<int, int> _lastBytes = {};
  final Map<int, int> _lastTs = {};

  int get activeCount => _active.length;

  int get parallelLimit {
    final v = SettingsService.instance.settings.downloadsParallel;
    return v < 1 ? 1 : v;
  }

  DownloadTask? taskById(int id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> init() async {
    if (_initDone) return;
    final client = Client(
      verifySSL: true,
      userAgent: 'AnterSurf/27.0.0 (AnterGet; libcurl)',
      connectTimeout: const Duration(seconds: 30),
      timeout: Duration.zero,
    );
    await client.init();
    _client = client;

    tasks.clear();
    tasks.addAll(await AppDatabase.instance.getDownloads());
    for (final t in tasks) {
      if (t.status == 'downloading') {
        final updated = t.copyWith(status: 'paused', speed: 0);
        await AppDatabase.instance.updateDownload(updated);
        _replace(updated);
      }
    }
    _initDone = true;
    notifyListeners();
  }

  /// Enqueue a download. Returns the new task id (or -1 on failure).
  Future<int> start(String url, {String? suggestedName}) async {
    if (url.isEmpty) return -1;
    try {
      await init();
    } catch (_) {
      return -1;
    }

    final dir = await _downloadsDir();
    var fileName = (suggestedName == null || suggestedName.isEmpty)
        ? _fileNameFromUrl(url)
        : suggestedName;
    fileName = _uniqueName(dir.path, fileName);

    final task = DownloadTask(
      url: url,
      fileName: fileName,
      path: p.join(dir.path, fileName),
      status: 'queued',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    task.id = await AppDatabase.instance.addDownload(task);
    tasks.insert(0, task);
    notifyListeners();
    _startNext();
    return task.id;
  }

  Future<void> retry(int id) async {
    final t = taskById(id);
    if (t == null || t.isActive || t.isDone) return;
    if (t.status == 'canceled') {
      t.received = 0;
      t.total = 0;
    }
    t.speed = 0;
    t.error = '';
    t.status = 'queued';
    await AppDatabase.instance.updateDownload(t);
    notifyListeners();
    _startNext();
  }

  Future<void> pause(int id) async {
    final t = taskById(id);
    if (t == null) return;
    if (t.status == 'queued') {
      t.status = 'paused';
      t.speed = 0;
      await AppDatabase.instance.updateDownload(t);
      notifyListeners();
      return;
    }
    if (t.status == 'downloading') {
      _pauseRequested.add(id);
      notifyListeners();
    }
  }

  Future<void> resume(int id) async {
    final t = taskById(id);
    if (t == null || t.status != 'paused') return;
    _lastBytes.remove(id);
    _lastTs.remove(id);
    t.status = 'queued';
    t.error = '';
    await AppDatabase.instance.updateDownload(t);
    notifyListeners();
    _startNext();
  }

  /// Cancel and delete the partial file (like desktop "Stop").
  Future<void> cancel(int id) async {
    final t = taskById(id);
    if (t == null) return;
    if (_active.contains(id)) {
      _cancelRequested.add(id);
      notifyListeners();
      return;
    }
    await _deletePartial(t);
    t.speed = 0;
    t.status = 'canceled';
    await AppDatabase.instance.updateDownload(t);
    notifyListeners();
  }

  /// Remove a task entirely (and its file).
  Future<void> remove(int id) async {
    final t = taskById(id);
    if (t == null) return;
    if (_active.contains(id)) {
      _cancelRequested.add(id);
      _removePending.add(id);
      notifyListeners();
      return;
    }
    await _deletePartial(t);
    await AppDatabase.instance.removeDownload(id);
    tasks.removeWhere((x) => x.id == id);
    _lastBytes.remove(id);
    _lastTs.remove(id);
    notifyListeners();
  }

  Future<void> clear() async {
    for (final t in List.of(tasks)) {
      if (_active.contains(t.id)) {
        _cancelRequested.add(t.id);
        _removePending.add(t.id);
      } else {
        await _deletePartial(t);
      }
    }
    await AppDatabase.instance.clearDownloads();
    tasks.clear();
    notifyListeners();
  }

  Future<void> open(int id) async {
    final t = taskById(id);
    if (t == null || !t.isDone || t.path.isEmpty) return;
    if (!File(t.path).existsSync()) {
      t.status = 'error';
      t.error = 'File no longer exists';
      await AppDatabase.instance.updateDownload(t);
      notifyListeners();
      return;
    }
    try {
      await OpenFilex.open(t.path);
    } catch (_) {}
  }

  // ---- engine -----------------------------------------------------------

  void _startNext() {
    if (_active.length >= parallelLimit) return;
    for (var i = tasks.length - 1; i >= 0; i--) {
      final t = tasks[i];
      if (t.status != 'queued') continue;
      if (_active.contains(t.id)) continue;
      _active.add(t.id);
      _run(t.id);
      if (_active.length >= parallelLimit) break;
    }
  }

  Future<void> _run(int id) async {
    final t = taskById(id);
    if (t == null) return;
    t.status = 'downloading';
    t.error = '';
    notifyListeners();
    await AppDatabase.instance.updateDownload(t);

    RandomAccessFile? raf;
    try {
      File(t.path).parent.createSync(recursive: true);
      raf = await File(t.path).open(mode: FileMode.append);
      _handles[id] = raf;

      if (t.total <= 0) {
        t.total = await _probeTotal(t.url);
        if (t.total < chunkSize) t.total = 0;
        notifyListeners();
      }

      var offset = t.received;
      var redirects = 0;

      while (true) {
        if (_pauseRequested.contains(id) || _cancelRequested.contains(id)) {
          break;
        }
        if (t.total > 0 && offset >= t.total) break;

        final end = t.total > 0
            ? min(offset + chunkSize - 1, t.total - 1)
            : offset + chunkSize - 1;

        final Response res;
        try {
          res = await _client!.send(Request(
            url: t.url,
            method: 'GET',
            headers: {'Range': 'bytes=$offset-$end'},
          ));
        } catch (e) {
          _fail(t, 'Network error: $e');
          break;
        }

        if (res.statusCode >= 300 && res.statusCode < 400) {
          final loc = _header(res.headers, 'location');
          if (loc != null && redirects < maxRedirects) {
            redirects++;
            t.url = Uri.parse(t.url).resolve(loc).toString();
            await AppDatabase.instance.updateDownload(t);
            notifyListeners();
            continue;
          }
          _fail(t, 'Too many redirects (${res.statusCode})');
          break;
        }
        redirects = 0;

        if (res.statusCode == 0 || res.errorCode != null) {
          _fail(t, res.errorMessage ?? 'Transfer failed');
          break;
        }

        if (res.statusCode == 416) {
          t.received = t.total > 0 ? t.total : offset;
          offset = t.received;
          break;
        }

        if (res.statusCode == 206) {
          final crTotal =
              _contentRangeTotal(_header(res.headers, 'content-range'));
          if (crTotal > 0) t.total = crTotal;
          final body = res.body;
          if (body.isEmpty) break;
          await raf!.writeFrom(body);
          offset += body.length;
          t.received = offset;
          _markSpeed(t);
          notifyListeners();
          await AppDatabase.instance.updateDownload(t);
          if (t.total > 0 && offset >= t.total) break;
          if (body.length < chunkSize) break;
          continue;
        }

        if (res.statusCode == 200) {
          // Server ignored Range. If a partial file exists, restart from
          // scratch (like curl -C - falling back to a fresh download).
          if (offset > 0) {
            raf!.close();
            _handles.remove(id);
            await File(t.path).delete();
            raf = await File(t.path).open(mode: FileMode.append);
            _handles[id] = raf;
            offset = 0;
            t.received = 0;
          }
          final body = res.body;
          if (body.isEmpty) break;
          await raf!.writeFrom(body);
          t.received = body.length;
          t.total = body.length;
          offset = t.received;
          _markSpeed(t);
          notifyListeners();
          await AppDatabase.instance.updateDownload(t);
          break;
        }

        _fail(t, 'HTTP ${res.statusCode}');
        break;
      }
    } catch (e) {
      _fail(t, 'Download failed: $e');
    } finally {
      if (raf != null) {
        try {
          await raf.close();
        } catch (_) {}
      }
      _handles.remove(id);
      _active.remove(id);

      final wasDownloading = t.status == 'downloading';
      if (wasDownloading) {
        if (_cancelRequested.contains(id)) {
          _cancelRequested.remove(id);
          t.status = 'canceled';
          t.speed = 0;
          await _deletePartial(t);
        } else if (_pauseRequested.contains(id)) {
          _pauseRequested.remove(id);
          t.status = 'paused';
          t.speed = 0;
        } else {
          if (t.total <= 0) t.total = t.received;
          t.status = 'completed';
          t.speed = 0;
        }
      } else {
        _cancelRequested.remove(id);
        _pauseRequested.remove(id);
      }

      if (t.status != 'paused') {
        _lastBytes.remove(id);
        _lastTs.remove(id);
      }

      if (_removePending.contains(id)) {
        _removePending.remove(id);
        await _deletePartial(t);
        await AppDatabase.instance.removeDownload(id);
        tasks.removeWhere((x) => x.id == id);
      } else {
        await AppDatabase.instance.updateDownload(t);
      }

      notifyListeners();
      _startNext();
    }
  }

  void _fail(DownloadTask t, String message) {
    t.status = 'error';
    t.error = message;
    t.speed = 0;
    notifyListeners();
    AppDatabase.instance.updateDownload(t);
  }

  void _markSpeed(DownloadTask t) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prevBytes = _lastBytes[t.id];
    final prevTs = _lastTs[t.id];
    if (prevBytes != null && prevTs != null && now > prevTs) {
      final dt = (now - prevTs) / 1000.0;
      final db = t.received - prevBytes;
      t.speed = dt > 0 ? (db / dt).round().clamp(0, 1 << 40).toInt() : 0;
    } else {
      t.speed = 0;
    }
    _lastBytes[t.id] = t.received;
    _lastTs[t.id] = now;
  }

  // ---- helpers ----------------------------------------------------------

  Future<int> _probeTotal(String url) async {
    var u = url;
    for (var i = 0; i < maxRedirects; i++) {
      try {
        final res = await _client!.send(Request(url: u, method: 'HEAD'));
        if (res.statusCode >= 300 && res.statusCode < 400) {
          final loc = _header(res.headers, 'location');
          if (loc == null) return 0;
          u = Uri.parse(u).resolve(loc).toString();
          continue;
        }
        if (res.statusCode == 0 || res.errorCode != null) return 0;
        return int.tryParse(_header(res.headers, 'content-length')) ?? 0;
      } catch (_) {
        return 0;
      }
    }
    return 0;
  }

  Future<Directory> _downloadsDir() async {
    Directory? dir;
    try {
      dir = await getExternalStorageDirectory();
    } catch (_) {}
    if (dir == null) {
      try {
        dir = await getApplicationDocumentsDirectory();
      } catch (_) {}
    }
    final dl = Directory(p.join(dir!.path, 'AnterSurf Downloads'));
    await dl.create(recursive: true);
    return dl;
  }

  String _fileNameFromUrl(String url) {
    try {
      final u = Uri.parse(url);
      final base = p.basename(u.path);
      if (base.isNotEmpty && base != '/' && base != '.') {
        try {
          return Uri.decodeComponent(base);
        } catch (_) {
          return base;
        }
      }
    } catch (_) {}
    final host = Uri.tryParse(url)?.host;
    return (host == null || host.isEmpty) ? 'download' : host;
  }

  String _uniqueName(String dir, String name) {
    var candidate = name;
    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var i = 1;
    while (File(p.join(dir, candidate)).existsSync()) {
      candidate = '$base ($i)$ext';
      i++;
    }
    return candidate;
  }

  Future<void> _deletePartial(DownloadTask t) async {
    if (t.path.isEmpty) return;
    try {
      final f = File(t.path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  void _replace(DownloadTask updated) {
    final i = tasks.indexWhere((x) => x.id == updated.id);
    if (i >= 0) tasks[i] = updated;
  }

  static String _header(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return '';
  }

  static int _contentRangeTotal(String cr) {
    if (cr.isEmpty) return 0;
    final m = RegExp(r'/(\d+)\s*$').firstMatch(cr.trim());
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }
}
