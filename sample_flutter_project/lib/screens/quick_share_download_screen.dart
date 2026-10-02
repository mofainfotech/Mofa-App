import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../services/background_download_task.dart';
import '../services/notification_service.dart';
import '../config/app_config.dart';

// Internal model for a format row in the UI
class _FormatOption {
  final String label;
  final String downloadUrl; // CDN URL for muxed, backend URL for merge/audio
  final bool isAudio;
  final int filesize; // in bytes, 0 if unknown
  final int qualityHeight; // 0 for audio

  const _FormatOption({
    required this.label,
    required this.downloadUrl,
    required this.isAudio,
    this.filesize = 0,
    this.qualityHeight = 0,
  });
}

class QuickShareDownloadScreen extends StatefulWidget {
  final String videoUrl;

  const QuickShareDownloadScreen({super.key, required this.videoUrl});

  @override
  State<QuickShareDownloadScreen> createState() => _QuickShareDownloadScreenState();
}

class _QuickShareDownloadScreenState extends State<QuickShareDownloadScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  String? _videoTitle;
  String? _thumbnail;
  List<_FormatOption> _formats = [];

  final _yt = YoutubeExplode();

  @override
  void initState() {
    super.initState();
    NotificationService().init();
    _fetchFormats();
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }

  Future<void> _fetchFormats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _formats = [];
    });

    try {
      // The phone's residential IP is used here — no bot detection!
      final videoId = VideoId(widget.videoUrl);
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      _videoTitle = video.title;
      // ThumbnailSet in 2.x: highResUrl
      _thumbnail = video.thumbnails.highResUrl;

      final options = <_FormatOption>[];
      final seenHeights = <int>{};

      // ── Muxed streams (video+audio combined) ─────────────────────────────
      // These are downloaded directly from googlevideo.com CDN — no backend needed
      final allowedHeights = {144, 240, 360, 480, 720};

      // Sort muxed by height descending
      final muxedSorted = manifest.muxed.toList()
        ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));

      for (final s in muxedSorted) {
        final h = s.videoResolution.height;
        if (!seenHeights.contains(h) && allowedHeights.contains(h)) {
          seenHeights.add(h);
          options.add(_FormatOption(
            label: '${h}p Video+Audio (mp4)',
            downloadUrl: s.url.toString(), // direct CDN URL — Dio downloads this
            isAudio: false,
            filesize: s.size.totalBytes.toInt(),
            qualityHeight: h,
          ));
        }
      }

      // ── Video-only 1080p+ → backend merges via CDN URLs ────────────────
      // We encode CDN URLs as POST-style GET params (single audio URL is manageable)
      // 1080p video URL + best audio URL passed to /api/merge on backend
      final videoOnlySorted = manifest.videoOnly.toList()
        ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));

      // Best AAC/MP4 audio stream for merging
      final allAudio = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.kiloBitsPerSecond.compareTo(a.bitrate.kiloBitsPerSecond));
      final bestAudioStream = allAudio.firstOrNull;

      for (final s in videoOnlySorted) {
        final h = s.videoResolution.height;
        if (!seenHeights.contains(h) && (h == 1080 || h == 1440 || h == 2160)) {
          seenHeights.add(h);
          if (bestAudioStream != null) {
            final vUrl = Uri.encodeComponent(s.url.toString());
            final aUrl = Uri.encodeComponent(bestAudioStream.url.toString());
            final titleEnc = Uri.encodeComponent(video.title);
            final backendMerge =
                '${AppConfig.backendUrl}/api/merge?video_url=$vUrl&audio_url=$aUrl&title=$titleEnc';
            options.add(_FormatOption(
              label: '${h}p Video+Audio (mp4 — merged)',
              downloadUrl: backendMerge,
              isAudio: false,
              filesize: s.size.totalBytes.toInt(),
              qualityHeight: h,
            ));
          }
        }
      }

      // Sort by quality descending
      options.sort((a, b) => b.qualityHeight - a.qualityHeight);

      // ── Best audio → MP3 via backend ─────────────────────────────────────
      if (bestAudioStream != null) {
        final kbps = bestAudioStream.bitrate.kiloBitsPerSecond.round();
        final aUrl = Uri.encodeComponent(bestAudioStream.url.toString());
        final titleEnc = Uri.encodeComponent(video.title);
        final backendAudio =
            '${AppConfig.backendUrl}/api/audio-cdn?audio_url=$aUrl&title=$titleEnc';
        options.add(_FormatOption(
          label: 'High Quality MP3 Audio ($kbps kbps)',
          downloadUrl: backendAudio,
          isAudio: true,
          filesize: bestAudioStream.size.totalBytes.toInt(),
          qualityHeight: 0,
        ));
      }

      if (!mounted) return;
      setState(() {
        _formats = options;
        _isLoading = false;
      });
    } on VideoUnplayableException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Video is unavailable: ${e.message}';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not fetch video info.\n${e.toString().split('\n').first}';
        _isLoading = false;
      });
    }
  }

  void _download(_FormatOption fmt) {
    BackgroundDownloadTask.startDownload(
      downloadUrl: fmt.downloadUrl,
      videoTitle: _videoTitle ?? 'YouTube Media',
      isAudio: fmt.isAudio,
      formatLabel: fmt.label,
      thumbnail: _thumbnail,
    );
    _closeAndExit(toastMessage: 'Download started');
  }

  void _closeAndExit({String? toastMessage}) {
    const platform = MethodChannel('com.example.sample_flutter_project/share');
    try {
      platform.invokeMethod('closeOverlay', {'toast': toastMessage});
    } catch (_) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _closeAndExit,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(18.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161626),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(Icons.download_for_offline,
                              color: Colors.redAccent, size: 26),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'YouTube Downloader',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white54, size: 22),
                            onPressed: _closeAndExit,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      if (_isLoading) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(
                                    color: Colors.redAccent),
                                SizedBox(height: 14),
                                Text(
                                  'Fetching video formats...',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (_errorMessage != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 36),
                              const SizedBox(height: 10),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchFormats,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Title + thumbnail
                        Row(
                          children: [
                            if (_thumbnail != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  _thumbnail!,
                                  width: 72,
                                  height: 46,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _videoTitle ?? 'YouTube Media',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Available Formats:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),

                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.45,
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _formats.length,
                            itemBuilder: (context, index) {
                              final fmt = _formats[index];
                              String? sizeString;
                              if (fmt.filesize > 0) {
                                final mb = fmt.filesize / (1024 * 1024);
                                sizeString = mb >= 1
                                    ? '${mb.toStringAsFixed(1)} MB'
                                    : '${(fmt.filesize / 1024).toStringAsFixed(0)} KB';
                              }

                              return Card(
                                color: const Color(0xFF1E1E2E),
                                margin:
                                    const EdgeInsets.symmetric(vertical: 3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListTile(
                                  dense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 2),
                                  leading: Icon(
                                    fmt.isAudio
                                        ? Icons.music_note
                                        : Icons.movie,
                                    color: fmt.isAudio
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                    size: 18,
                                  ),
                                  title: Text(
                                    fmt.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: sizeString != null
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                              top: 2.0),
                                          child: Text(
                                            sizeString,
                                            style: const TextStyle(
                                              color: Colors.lightBlueAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      : null,
                                  trailing: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white12,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      minimumSize: const Size(56, 30),
                                    ),
                                    onPressed: () => _download(fmt),
                                    child: const Text('Download',
                                        style: TextStyle(fontSize: 11)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
