import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_theme.dart';
import '../controllers/browser_controller.dart';
import '../models/download_task.dart';
import '../services/anterget_service.dart';

class DownloadsScreen extends StatelessWidget {
  final BrowserController controller;
  const DownloadsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    return Positioned.fill(
      child: Material(
        color: scheme.background,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: controller.toggleDownloads,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Downloads",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        ListenableBuilder(
                          listenable: AnterGetService.instance,
                          builder: (context, _) {
                            final active =
                                AnterGetService.instance.activeCount;
                            return Text(
                              active > 0
                                  ? "$active active · AnterGet"
                                  : "AnterGet engine",
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurface.withValues(alpha: .6),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  ListenableBuilder(
                    listenable: AnterGetService.instance,
                    builder: (context, _) {
                      final tasks = AnterGetService.instance.tasks;
                      if (tasks.isEmpty) return const SizedBox.shrink();
                      return TextButton.icon(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppTheme.scheme().surface,
                              title: const Text("Clear all downloads?"),
                              content: const Text(
                                  "This removes all downloads and deletes "
                                  "their files."),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text("Cancel"),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text("Clear"),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await AnterGetService.instance.clear();
                          }
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text("Clear"),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildList()),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                "Powered by libcurl · AnterGet",
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: .45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final scheme = AppTheme.scheme();
    return ListenableBuilder(
      listenable: AnterGetService.instance,
      builder: (context, _) {
        final service = AnterGetService.instance;
        final items = service.tasks;
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.download_rounded,
                      size: 36, color: scheme.primary),
                ),
                const SizedBox(height: 16),
                Text("No downloads yet",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
                const SizedBox(height: 6),
                Text(
                  "Download a file on the web and it will appear here.\n"
                  "You can pause, resume and open files.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface.withValues(alpha: .55)),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          itemCount: items.length,
          itemBuilder: (context, i) => _DownloadCard(task: items[i]),
        );
      },
    );
  }
}

class _DownloadCard extends StatelessWidget {
  final DownloadTask task;
  const _DownloadCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.scheme();
    final service = AnterGetService.instance;
    final done = task.isDone;
    final downloading = task.status == 'downloading';
    final paused = task.status == 'paused';
    final queued = task.status == 'queued';
    final error = task.status == 'error';
    final canceled = task.status == 'canceled';

    final determinate = task.total > 0;
    final progress = (task.progress / 100).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_fileIcon(task.fileName),
                  size: 22, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      )),
                  const SizedBox(height: 4),
                  if (downloading || queued) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: determinate ? progress : null,
                        minHeight: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _metaLine(
                      _progressText(),
                      task.speed > 0 ? _speedText() : null,
                    ),
                  ] else if (paused) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: determinate ? progress : null,
                        minHeight: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _metaLine(_progressText(), null),
                  ] else if (error) ...[
                    Text(
                      task.error.isEmpty ? "Download failed" : task.error,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.error),
                    ),
                  ] else if (canceled) ...[
                    Text("Canceled",
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: .55))),
                  ] else ...[
                    Text(
                      "${_bytes(task.total)} · Done",
                      style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: .55)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                if (downloading)
                  _action(Icons.pause_rounded, "Pause",
                      () => service.pause(task.id))
                else if (paused)
                  _action(Icons.play_arrow_rounded, "Resume",
                      () => service.resume(task.id))
                else if (queued)
                  _action(Icons.close_rounded, "Cancel",
                      () => service.cancel(task.id))
                else if (done)
                  _action(Icons.folder_open_rounded, "Open",
                      () => service.open(task.id))
                else if (error || canceled)
                  _action(Icons.refresh_rounded, "Retry",
                      () => service.retry(task.id))
                else
                  const SizedBox(height: 36),
                const SizedBox(height: 2),
                IconButton(
                  icon: Icon(
                    task.isDone || task.path.isEmpty
                        ? Icons.delete_outline
                        : Icons.delete_forever_outlined,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  color: scheme.onSurface.withValues(alpha: .6),
                  onPressed: () => service.remove(task.id),
                  tooltip: task.isDone ? "Delete file" : "Cancel & delete",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String tooltip, VoidCallback onTap) {
    final scheme = AppTheme.scheme();
    return IconButton(
      icon: Icon(icon, size: 22),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      color: scheme.primary,
      tooltip: tooltip,
      onPressed: onTap,
    );
  }

  Widget _metaLine(String left, String? right) {
    final scheme = AppTheme.scheme();
    return Row(
      children: [
        Expanded(
          child: Text(left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: .7))),
        ),
        if (right != null)
          Text(right,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _progressText() {
    final done = task.received / max(task.total, 1);
    final pct = task.total > 0 ? task.progress.round() : (done * 100).round();
    final size = task.total > 0
        ? "${_bytes(task.received)} / ${_bytes(task.total)}"
        : _bytes(task.received);
    if (task.status == 'queued') return "Waiting…";
    if (task.status == 'paused') return "Paused · $pct% · $size";
    final eta = task.speed > 0 && task.total > task.received
        ? " · ${_eta((task.total - task.received) ~/ task.speed)} left"
        : "";
    return "$pct% · $size$eta";
  }

  String _speedText() => "${_speed(task.speed)}/s";
}

String _bytes(int n) {
  if (n <= 0) return "0 B";
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = n.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits)} ${units[u]}';
}

String _speed(int bps) => _bytes(bps);

String _eta(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m < 60) return '${m}m ${s}s';
  final h = m ~/ 60;
  return '${h}h ${m % 60}m';
}

IconData _fileIcon(String name) {
  final ext = p.extension(name).toLowerCase();
  if (ext == '.zip' || ext == '.tar' || ext == '.gz' || ext == '.bz2' ||
      ext == '.7z' || ext == '.rar' || ext == '.xz') {
    return Icons.folder_zip_outlined;
  }
  if (ext == '.apk') return Icons.android;
  if (ext == '.exe' || ext == '.msi') return Icons.settings_applications;
  if (ext == '.dmg' || ext == '.pkg') return Icons.laptop_mac_outlined;
  if (ext == '.deb' || ext == '.rpm' || ext == '.AppImage') {
    return Icons.terminal;
  }
  if (ext == '.mp4' || ext == '.mkv' || ext == '.avi' || ext == '.mov' ||
      ext == '.webm') {
    return Icons.movie_outlined;
  }
  if (ext == '.mp3' || ext == '.wav' || ext == '.flac' || ext == '.ogg' ||
      ext == '.m4a') {
    return Icons.music_note_outlined;
  }
  if (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.gif' ||
      ext == '.webp' || ext == '.svg') {
    return Icons.image_outlined;
  }
  if (ext == '.pdf') return Icons.picture_as_pdf_outlined;
  if (ext == '.doc' || ext == '.docx') return Icons.description_outlined;
  if (ext == '.txt' || ext == '.md') return Icons.article_outlined;
  return Icons.insert_drive_file_outlined;
}
