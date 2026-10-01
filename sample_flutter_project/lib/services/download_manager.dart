import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'notification_service.dart';

class DownloadItem {
  final int id;
  final String title;
  final String formatLabel;
  final bool isAudio;
  final String downloadUrl;
  final String? thumbnail;
  String savePath;
  double progress; // 0.0 to 1.0 (-1.0 for indeterminate)
  String status; // 'downloading', 'completed', 'failed'
  String statusText;
  int receivedBytes;
  int totalBytes;
  String? errorMessage;
  final DateTime startedAt;
  DateTime? completedAt;
  CancelToken? cancelToken;

  DownloadItem({
    required this.id,
    required this.title,
    required this.formatLabel,
    required this.isAudio,
    required this.downloadUrl,
    required this.savePath,
    this.thumbnail,
    this.progress = 0.0,
    this.status = 'downloading',
    this.statusText = 'Starting...',
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.cancelToken,
    DateTime? startedAt,
    this.completedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  String get formattedSize {
    if (totalBytes > 0) {
      final mb = totalBytes / (1024 * 1024);
      return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(totalBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '';
  }
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final List<DownloadItem> _items = [];
  bool _initialized = false;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 15),
    ),
  );

  List<DownloadItem> get allDownloads => List.unmodifiable(_items);
  List<DownloadItem> get activeDownloads => _items.where((i) => i.status == 'downloading').toList();
  List<DownloadItem> get completedDownloads => _items.where((i) => i.status == 'completed').toList();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadExistingDownloads();
  }

  Future<void> _loadExistingDownloads() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (!dir.existsSync()) return;

      final files = dir.listSync();
      for (final entity in files) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.endsWith('.mp4') || name.endsWith('.mp3')) {
            final isAudio = name.endsWith('.mp3');
            // Clean up the file name for display
            String displayTitle = name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
            displayTitle = displayTitle.replaceAll(RegExp(r'_\d+$'), '');
            displayTitle = displayTitle.replaceAll('_', ' ').trim();
            if (displayTitle.isEmpty) displayTitle = 'YouTube Media';

            final stat = entity.statSync();
            final bytes = stat.size;

            final existing = _items.any((item) => item.savePath == entity.path);
            if (!existing) {
              _items.add(
                DownloadItem(
                  id: entity.path.hashCode,
                  title: displayTitle,
                  formatLabel: isAudio ? 'MP3 Audio' : 'MP4 Video',
                  isAudio: isAudio,
                  downloadUrl: '',
                  savePath: entity.path,
                  progress: 1.0,
                  status: 'completed',
                  statusText: 'Downloaded',
                  totalBytes: bytes,
                  receivedBytes: bytes,
                  startedAt: stat.modified,
                  completedAt: stat.modified,
                ),
              );
            }
          }
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> startDownload({
    required String downloadUrl,
    required String videoTitle,
    required bool isAudio,
    required String formatLabel,
    String? thumbnail,
  }) async {
    final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ext = isAudio ? 'mp3' : 'mp4';
    final cleanTitle = videoTitle.replaceAll(RegExp(r'[^\w\s\-]'), '_').trim();
    final fileName = '${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/$fileName';
    final cancelToken = CancelToken();

    final item = DownloadItem(
      id: notifId,
      title: videoTitle,
      formatLabel: formatLabel,
      isAudio: isAudio,
      downloadUrl: downloadUrl,
      savePath: savePath,
      thumbnail: thumbnail,
      cancelToken: cancelToken,
      status: 'downloading',
      progress: 0.0,
      statusText: 'Starting...',
    );

    _items.insert(0, item);
    notifyListeners();

    // Show initial notification
    await NotificationService().showProgressNotification(
      id: notifId,
      title: 'Downloading $videoTitle',
      body: 'Starting download ($formatLabel)...',
      progress: 0,
      maxProgress: 100,
      indeterminate: true,
    );

    int lastReportedPercent = -1;

    try {
      await _dio.download(
        downloadUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          item.receivedBytes = received;
          item.totalBytes = total > 0 ? total : 0;

          if (total > 0) {
            final progress = received / total;
            final percent = (progress * 100).toInt();
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);

            item.progress = progress;
            item.statusText = '$receivedMb MB / $totalMb MB ($percent%)';

            if (percent != lastReportedPercent) {
              lastReportedPercent = percent;
              NotificationService().showProgressNotification(
                id: notifId,
                title: 'Downloading $videoTitle',
                body: '$receivedMb MB / $totalMb MB ($percent%)',
                progress: percent,
                maxProgress: 100,
              );
            }
          } else {
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
            item.progress = -1.0;
            item.statusText = '$receivedMb MB downloaded...';

            NotificationService().showProgressNotification(
              id: notifId,
              title: 'Downloading $videoTitle',
              body: '$receivedMb MB downloaded...',
              progress: 0,
              maxProgress: 100,
              indeterminate: true,
            );
          }
          notifyListeners();
        },
      );

      // Successfully downloaded
      item.status = 'completed';
      item.progress = 1.0;
      item.statusText = 'Downloaded';
      item.completedAt = DateTime.now();

      // Save video to Gallery
      if (!isAudio) {
        try {
          await Gal.putVideo(savePath);
        } catch (_) {}
      } else {
        try {
          final publicDownloadDir = Directory('/storage/emulated/0/Download');
          if (publicDownloadDir.existsSync()) {
            final publicFile = File('${publicDownloadDir.path}/$fileName');
            await File(savePath).copy(publicFile.path);
          }
        } catch (_) {}
      }

      await NotificationService().showCompletedNotification(
        id: notifId,
        title: 'Download Complete',
        body: '$videoTitle saved successfully!',
      );

      notifyListeners();
    } catch (e) {
      if (cancelToken.isCancelled) {
        item.status = 'failed';
        item.statusText = 'Cancelled';
        await NotificationService().cancelNotification(notifId);
      } else {
        item.status = 'failed';
        item.statusText = 'Failed';
        item.errorMessage = e.toString();
        await NotificationService().showFailedNotification(
          id: notifId,
          title: 'Download Failed',
          body: 'Error downloading $videoTitle: $e',
        );
      }
      notifyListeners();
    }
  }

  void cancelDownload(int id) {
    try {
      final item = _items.firstWhere((i) => i.id == id);
      if (item.status == 'downloading') {
        item.cancelToken?.cancel('User cancelled download');
        item.status = 'failed';
        item.statusText = 'Cancelled';
        NotificationService().cancelNotification(id);
        notifyListeners();
      }
    } catch (_) {}
  }


  Future<void> deleteDownload(DownloadItem item) async {
    try {
      final file = File(item.savePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
    _items.removeWhere((i) => i.id == item.id || i.savePath == item.savePath);
    notifyListeners();
  }
}
