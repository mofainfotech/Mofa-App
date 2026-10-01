import 'download_manager.dart';

class BackgroundDownloadTask {
  static void startDownload({
    required String downloadUrl,
    required String videoTitle,
    required bool isAudio,
    required String formatLabel,
    String? thumbnail,
  }) {
    DownloadManager().startDownload(
      downloadUrl: downloadUrl,
      videoTitle: videoTitle,
      isAudio: isAudio,
      formatLabel: formatLabel,
      thumbnail: thumbnail,
    );
  }
}
