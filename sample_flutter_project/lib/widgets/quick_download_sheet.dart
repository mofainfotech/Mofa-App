import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../services/notification_service.dart';

class QuickDownloadSheet extends StatefulWidget {
  final String videoUrl;

  const QuickDownloadSheet({super.key, required this.videoUrl});

  static Future<void> show(BuildContext context, String url) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickDownloadSheet(videoUrl: url),
    );
  }

  @override
  State<QuickDownloadSheet> createState() => _QuickDownloadSheetState();
}

class _QuickDownloadSheetState extends State<QuickDownloadSheet> {
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _videoData;

  bool _isDownloading = false;
  String? _downloadingLabel;
  double _downloadProgress = 0.0;
  String _downloadStatusText = '';

  @override
  void initState() {
    super.initState();
    NotificationService().init();
    _fetchFormats();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _fetchFormats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendUrl}/api/formats?url=${Uri.encodeComponent(widget.videoUrl)}'),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _videoData = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Could not load formats (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Connection failed: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _download(String downloadUrl, String label, bool isAudio) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadingLabel = label;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Starting...';
    });

    _cancelToken = CancelToken();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = isAudio ? 'mp3' : 'mp4';
      final rawTitle = (_videoData?['title'] ?? 'video').toString();
      final cleanTitle = rawTitle.replaceAll(RegExp(r'[^\w\s\-]'), '_').trim();
      final fileName = '${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final savePath = '${dir.path}/$fileName';

      final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int lastReportedPercent = -1;

      await _dio.download(
        downloadUrl,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          if (total != -1) {
            final progress = received / total;
            final percent = (progress * 100).toInt();
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);

            setState(() {
              _downloadProgress = progress;
              _downloadStatusText = '$receivedMb MB / $totalMb MB ($percent%)';
            });

            if (percent != lastReportedPercent) {
              lastReportedPercent = percent;
              NotificationService().showProgressNotification(
                id: notifId,
                title: 'Downloading $rawTitle',
                body: '$receivedMb MB / $totalMb MB ($percent%)',
                progress: percent,
                maxProgress: 100,
              );
            }
          } else {
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _downloadProgress = -1.0;
              _downloadStatusText = '$receivedMb MB (processing...)';
            });
            NotificationService().showProgressNotification(
              id: notifId,
              title: 'Downloading $rawTitle',
              body: '$receivedMb MB downloaded...',
              progress: 0,
              maxProgress: 100,
              indeterminate: true,
            );
          }
        },
      );

      if (!isAudio) {
        try {
          await Gal.putVideo(savePath);
        } catch (_) {}
      }

      await NotificationService().showCompletedNotification(
        id: notifId,
        title: 'Download Complete',
        body: '$rawTitle saved successfully!',
      );

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadStatusText = 'Downloaded successfully!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadStatusText = 'Failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161626),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              const Icon(Icons.download_for_offline, color: Colors.redAccent, size: 26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Quick Download',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Downloading progress bar banner
          if (_isDownloading || _downloadStatusText.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isDownloading ? Icons.cloud_download : Icons.check_circle,
                        color: _isDownloading ? Colors.redAccent : Colors.greenAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _downloadingLabel ?? 'Downloading',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          maxLines: 1,
                        ),
                      ),
                      if (_isDownloading)
                        GestureDetector(
                          onTap: () {
                            _cancelToken?.cancel();
                            setState(() {
                              _isDownloading = false;
                              _downloadStatusText = 'Cancelled';
                            });
                          },
                          child: const Icon(Icons.close, color: Colors.white60, size: 18),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _downloadProgress < 0 ? null : _downloadProgress,
                      backgroundColor: Colors.white12,
                      color: Colors.redAccent,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _downloadStatusText,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],

          if (_isLoading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.redAccent),
                    SizedBox(height: 16),
                    Text('Fetching video formats...', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ] else if (_errorMessage != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchFormats,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ] else if (_videoData != null) ...[
            // Video title preview
            Row(
              children: [
                if (_videoData!['thumbnail'] != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _videoData!['thumbnail'],
                      width: 80,
                      height: 50,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _videoData!['title'] ?? 'YouTube Media',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Format:',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            // Formats List
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: (_videoData!['formats'] as List? ?? []).length,
                itemBuilder: (context, index) {
                  final fmt = (_videoData!['formats'] as List)[index];
                  final label = fmt['label'] ?? 'Format';
                  final downloadUrl = fmt['download_url'] ?? '';
                  final isAudio = fmt['type'] == 'audio';
                  final filesize = fmt['filesize'];

                  String? sizeString;
                  if (filesize != null && filesize is num && filesize > 0) {
                    final mb = filesize / (1024 * 1024);
                    sizeString = mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(filesize / 1024).toStringAsFixed(0)} KB';
                  }

                  final isThisDownloading = _isDownloading && _downloadingLabel == label;

                  return Card(
                    color: const Color(0xFF1E1E2E),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        isAudio ? Icons.music_note : Icons.movie,
                        color: isAudio ? Colors.greenAccent : Colors.redAccent,
                        size: 20,
                      ),
                      title: Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      subtitle: sizeString != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      sizeString,
                                      style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isThisDownloading ? Colors.redAccent.withValues(alpha: 0.2) : Colors.white12,
                          foregroundColor: isThisDownloading ? Colors.redAccent : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: const Size(60, 32),
                        ),
                        onPressed: downloadUrl.isNotEmpty && !_isDownloading
                            ? () => _download(downloadUrl, label, isAudio)
                            : null,
                        child: isThisDownloading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                              )
                            : const Text('Download', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
