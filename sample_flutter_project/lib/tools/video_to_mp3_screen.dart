import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audio_converter_native/audio_converter_native.dart';
import 'package:path_provider/path_provider.dart';

class VideoToMp3Screen extends StatefulWidget {
  const VideoToMp3Screen({super.key});

  @override
  State<VideoToMp3Screen> createState() => _VideoToMp3ScreenState();
}

class _VideoToMp3ScreenState extends State<VideoToMp3Screen> {
  String? _videoPath;
  String? _videoName;
  bool _isConverting = false;
  String _statusMessage = "Select a video to start";

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result != null) {
      setState(() {
        _videoPath = result.files.single.path;
        _videoName = result.files.single.name;
        _statusMessage = "Video selected: $_videoName";
      });
    }
  }

  Future<void> _convert() async {
    if (_videoPath == null) return;

    setState(() {
      _isConverting = true;
      _statusMessage = "Extracting Audio...";
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 15),
            Text('Processing... please wait'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // The correct API for audio_converter_native 1.0.4
      final result = await AudioConverterService.instance.convertToMP3(
        inputPath: _videoPath!,
      );

      if (result.success && result.outputPath != null) {
        final resultPath = result.outputPath!;
        final outName = "audio_${DateTime.now().millisecondsSinceEpoch}.mp3";
        final publicDir = Directory('/storage/emulated/0/Download/mofa_audio');
        if (!await publicDir.exists()) await publicDir.create(recursive: true);
        
        final destinationPath = "${publicDir.path}/$outName";
        await File(resultPath).copy(destinationPath);

        if (mounted) {
          setState(() {
            _isConverting = false;
            _statusMessage = "Saved to Downloads/mofa_audio";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 8),
              content: Text('MP3 Saved! Downloads/mofa_audio/$outName'),
              action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
            ),
          );
        }
      } else {
        throw "Extraction failed. The native encoder returned an empty path.";
      }
    } catch (e) {
      debugPrint("Conversion Error: $e");
      if (mounted) {
        setState(() {
          _isConverting = false;
          _statusMessage = "Error: $e";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Video to MP3 (Native)'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade700, Colors.indigo.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5)),
                ],
              ),
              child: const Column(
                children: [
                  Icon(Icons.music_video, size: 64, color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Native Audio Extraction',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No FFmpeg needed - Uses phone hardware',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Selection Section
            Card(
              elevation: 0,
              color: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15), 
                side: BorderSide(color: Colors.white.withOpacity(0.05))
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.video_file, color: Colors.indigoAccent),
                ),
                title: const Text('Select Video', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text(_videoName ?? 'Choose a video file', style: const TextStyle(color: Colors.white60)),
                trailing: _videoPath != null 
                  ? IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => setState(() { _videoPath = null; _videoName = null; _statusMessage="Select a video to start"; }))
                  : const Icon(Icons.chevron_right, color: Colors.white60),
                onTap: _isConverting ? null : _pickVideo,
              ),
            ),
            const SizedBox(height: 40),

            // Convert Button
            ElevatedButton.icon(
              onPressed: (_videoPath == null || _isConverting) ? null : _convert,
              icon: _isConverting 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.flash_on),
              label: Text(_isConverting ? "EXTRACTING..." : "CONVERT TO MP3"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigoAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
            ),
            
            const SizedBox(height: 20),
            Text(_statusMessage, style: TextStyle(color: _statusMessage.contains('Error') ? Colors.redAccent : Colors.white70, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
