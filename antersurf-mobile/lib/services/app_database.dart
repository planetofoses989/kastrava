import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/bookmark.dart';
import '../models/download_task.dart';
import '../models/history_entry.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._();
  AppDatabase._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'antersurf.db');
    return openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          for (final col in const {
            'received INTEGER NOT NULL DEFAULT 0',
            'total INTEGER NOT NULL DEFAULT 0',
            'speed INTEGER NOT NULL DEFAULT 0',
            'error TEXT',
          }) {
            try {
              await db.execute('ALTER TABLE downloads ADD COLUMN $col');
            } catch (_) {}
          }
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            favicon TEXT,
            created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            favicon TEXT,
            visited_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE downloads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            file_name TEXT NOT NULL,
            path TEXT,
            received INTEGER NOT NULL DEFAULT 0,
            total INTEGER NOT NULL DEFAULT 0,
            speed INTEGER NOT NULL DEFAULT 0,
            status TEXT,
            error TEXT,
            created_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE top_sites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            sort_order INTEGER
          )
        ''');
      },
    );
  }

  Future<List<Bookmark>> getBookmarks() async {
    final d = await db;
    final rows = await d.query('bookmarks', orderBy: 'created_at DESC');
    return rows.map(Bookmark.fromMap).toList();
  }

  Future<bool> isBookmarked(String url) async {
    final d = await db;
    final rows = await d.query('bookmarks', where: 'url = ?', whereArgs: [url], limit: 1);
    return rows.isNotEmpty;
  }

  Future<int> addBookmark(Bookmark b) async {
    final d = await db;
    final existing = await d.query('bookmarks', where: 'url = ?', whereArgs: [b.url], limit: 1);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return d.insert('bookmarks', b.toMap()..remove('id'));
  }

  Future<int> deleteBookmark(int id) async {
    final d = await db;
    return d.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteBookmarkByUrl(String url) async {
    final d = await db;
    return d.delete('bookmarks', where: 'url = ?', whereArgs: [url]);
  }

  Future<void> clearBookmarks() async {
    final d = await db;
    await d.delete('bookmarks');
  }

  Future<List<HistoryEntry>> getHistory({int limit = 500}) async {
    final d = await db;
    final rows = await d.query('history', orderBy: 'visited_at DESC', limit: limit);
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<void> addHistory(HistoryEntry h) async {
    final d = await db;
    if (h.url.isEmpty) return;
    if (h.url.startsWith('about:') || h.url.startsWith('data:')) return;
    final existing = await d.query('history',
        where: 'url = ?', whereArgs: [h.url], limit: 1);
    if (existing.isNotEmpty) {
      await d.update('history', {'visited_at': h.visitedAt},
          where: 'url = ?', whereArgs: [h.url]);
    } else {
      await d.insert('history', h.toMap()..remove('id'));
    }
  }

  Future<void> clearHistory() async {
    final d = await db;
    await d.delete('history');
  }

  Future<List<DownloadTask>> getDownloads() async {
    final d = await db;
    final rows = await d.query('downloads', orderBy: 'created_at DESC');
    return rows.map(DownloadTask.fromMap).toList();
  }

  Future<int> addDownload(DownloadTask t) async {
    final d = await db;
    return d.insert('downloads', t.toMap()..remove('id'));
  }

  Future<void> updateDownload(DownloadTask t) async {
    final d = await db;
    await d.update('downloads', t.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [t.id]);
  }

  Future<void> removeDownload(int id) async {
    final d = await db;
    await d.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearDownloads() async {
    final d = await db;
    await d.delete('downloads');
  }

  Future<List<Map<String, dynamic>>> getTopSites() async {
    final d = await db;
    return d.query('top_sites', orderBy: 'sort_order ASC');
  }

  Future<void> addTopSite(String title, String url) async {
    final d = await db;
    final count = Sqflite.firstIntValue(
        await d.rawQuery('SELECT COUNT(*) FROM top_sites'));
    await d.insert('top_sites', {
      'title': title,
      'url': url,
      'sort_order': (count ?? 0) + 1,
    });
  }

  Future<void> removeTopSite(int id) async {
    final d = await db;
    await d.delete('top_sites', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearTopSites() async {
    final d = await db;
    await d.delete('top_sites');
  }
}
