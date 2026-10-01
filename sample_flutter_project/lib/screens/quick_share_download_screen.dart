import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/background_download_task.dart';
import '../services/notification_service.dart';

class QuickShareDownloadScreen extends StatefulWidget {
  final String videoUrl;

  const QuickShareDownloadScreen({super.key, required this.videoUrl});

  @override
  State<QuickShareDownloadScreen> createState() => _QuickShareDownloadScreenState();
}

class _QuickShareDownloadScreenState extends State<QuickShareDownloadScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _videoData;

  @override
  void initState() {
    super.initState();
    NotificationService().init();
    _fetchFormats();
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

  void _download(String downloadUrl, String label, bool isAudio) {
    // 1. Start actual background download immediately
    BackgroundDownloadTask.startDownload(
      downloadUrl: downloadUrl,
      videoTitle: _videoData?['title'] ?? 'YouTube Media',
      isAudio: isAudio,
      formatLabel: label,
      thumbnail: _videoData?['thumbnail'],
    );

    // 2. Hand off to background and close popup overlay quickly, showing toast
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
          // Tapping outside the card closes the popup overlay cleanly
          GestureDetector(
            onTap: _closeAndExit,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: GestureDetector(
                onTap: () {}, // Prevent taps inside card from closing
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
                      // Header with Close Button
                      Row(
                        children: [
                          const Icon(Icons.download_for_offline, color: Colors.redAccent, size: 26),
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
                            icon: const Icon(Icons.close, color: Colors.white54, size: 22),
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
                                CircularProgressIndicator(color: Colors.redAccent),
                                SizedBox(height: 14),
                                Text(
                                  'Fetching video formats...',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
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
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                              const SizedBox(height: 10),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
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
                      ] else if (_videoData != null) ...[
                        // Video title & thumbnail preview
                        Row(
                          children: [
                            if (_videoData!['thumbnail'] != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  _videoData!['thumbnail'],
                                  width: 72,
                                  height: 46,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _videoData!['title'] ?? 'YouTube Media',
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

                        // Formats List
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.45,
                          ),
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
                                sizeString = mb >= 1
                                    ? '${mb.toStringAsFixed(1)} MB'
                                    : '${(filesize / 1024).toStringAsFixed(0)} KB';
                              }

                              return Card(
                                color: const Color(0xFF1E1E2E),
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 2,
                                  ),
                                  leading: Icon(
                                    isAudio ? Icons.music_note : Icons.movie,
                                    color: isAudio ? Colors.greenAccent : Colors.redAccent,
                                    size: 18,
                                  ),
                                  title: Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: sizeString != null
                                      ? Padding(
                                          padding: const EdgeInsets.only(top: 2.0),
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
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      minimumSize: const Size(56, 30),
                                    ),
                                    onPressed: downloadUrl.isNotEmpty
                                        ? () => _download(downloadUrl, label, isAudio)
                                        : null,
                                    child: const Text('Download', style: TextStyle(fontSize: 11)),
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
