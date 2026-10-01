import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../screens/downloads_screen.dart';
import '../services/notification_service.dart';


class YTDownloaderScreen extends StatefulWidget {
  final String? initialUrl;
  const YTDownloaderScreen({super.key, this.initialUrl});

  @override
  State<YTDownloaderScreen> createState() => _YTDownloaderScreenState();
}

class _YTDownloaderScreenState extends State<YTDownloaderScreen> {
  late final TextEditingController _urlController;
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _videoData;

  // In-app download tracking state
  String? _activeDownloadLabel;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  String _downloadStatusText = '';

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl ?? '');
    NotificationService().init();
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchVideoFormats();
      });
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _fetchVideoFormats() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Please enter a valid YouTube URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _videoData = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendUrl}/api/formats?url=${Uri.encodeComponent(url)}'),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _videoData = data;
          _isLoading = false;
        });
      } else {
        try {
          final data = jsonDecode(response.body);
          setState(() {
            _errorMessage = data['error'] ?? 'Server error (${response.statusCode})';
            _isLoading = false;
          });
        } catch (_) {
          setState(() {
            _errorMessage = 'Server returned error ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not connect to backend: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startInAppDownload(String downloadUrl, String label, bool isAudio) async {
    if (_isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A download is already in progress...')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _activeDownloadLabel = label;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Starting download...';
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
              _downloadProgress = -1.0; // indeterminate
              _downloadStatusText = '$receivedMb MB downloaded (processing...)';
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

      // Save to device media gallery if video
      if (!isAudio) {
        try {
          await Gal.putVideo(savePath);
        } catch (_) {
          // If Gal permission fails or not supported, file is still saved in documents
        }
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
        _downloadStatusText = 'Saved: $fileName';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded successfully: $fileName'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e as DioException)) {
        setState(() {
          _isDownloading = false;
          _downloadStatusText = 'Download cancelled';
        });
      } else {
        setState(() {
          _isDownloading = false;
          _downloadStatusText = 'Download failed: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('Cancelled by user');
    setState(() {
      _isDownloading = false;
      _downloadProgress = 0.0;
      _downloadStatusText = 'Cancelled';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('YouTube Downloader'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'View Downloads',
            icon: const Icon(Icons.download_done_rounded, color: Colors.redAccent),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Paste YouTube URL...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                filled: true,
                fillColor: const Color(0xFF1E1E2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.link, color: Colors.redAccent),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white54),
                  onPressed: () => _urlController.clear(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _fetchVideoFormats,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search),
              label: Text(_isLoading ? 'Fetching...' : 'Get Download Links'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            // In-app Download Progress Card
            if (_isDownloading || _downloadStatusText.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isDownloading ? Colors.redAccent.withValues(alpha: 0.4) : Colors.white12,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isDownloading ? Icons.cloud_download : Icons.check_circle_outline,
                          color: _isDownloading ? Colors.redAccent : Colors.greenAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _activeDownloadLabel ?? 'Downloading',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isDownloading)
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                            onPressed: _cancelDownload,
                            tooltip: 'Cancel Download',
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _downloadProgress < 0 ? null : _downloadProgress,
                        backgroundColor: Colors.white10,
                        color: Colors.redAccent,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _downloadStatusText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
            if (_videoData != null) ...[
              const SizedBox(height: 24),
              if (_videoData!['thumbnail'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _videoData!['thumbnail'],
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _videoData!['title'] ?? 'YouTube Media',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Available Formats:',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (_videoData!['formats'] is List)
                ...(_videoData!['formats'] as List).map((fmt) {
                  final label = fmt['label'] ?? 'Format';
                  final downloadUrl = fmt['download_url'] ?? '';
                  final isAudio = fmt['type'] == 'audio';
                  final isThisDownloading = _isDownloading && _activeDownloadLabel == label;

                  final filesize = fmt['filesize'];
                  String? sizeString;
                  if (filesize != null && filesize is num && filesize > 0) {
                    final mb = filesize / (1024 * 1024);
                    sizeString = mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(filesize / 1024).toStringAsFixed(0)} KB';
                  }

                  return Card(
                    color: const Color(0xFF1E1E2E),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      leading: Icon(
                        isAudio ? Icons.music_note : Icons.movie,
                        color: isAudio ? Colors.greenAccent : Colors.redAccent,
                      ),
                      title: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: sizeString != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      sizeString,
                                      style: const TextStyle(
                                        color: Colors.lightBlueAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isThisDownloading ? Colors.redAccent.withValues(alpha: 0.2) : Colors.white10,
                          foregroundColor: isThisDownloading ? Colors.redAccent : Colors.white,
                        ),
                        onPressed: downloadUrl.isNotEmpty && !_isDownloading
                            ? () => _startInAppDownload(downloadUrl, label, isAudio)
                            : null,
                        child: isThisDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                              )
                            : const Text('Download'),
                      ),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }
}
