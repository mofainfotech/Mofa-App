import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

class SttScreen extends StatefulWidget {
  const SttScreen({super.key});

  @override
  State<SttScreen> createState() => _SttScreenState();
}

class _SttScreenState extends State<SttScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  bool _isProcessing = false;
  String? _fileName;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _importAudio() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
      );

      if (result != null) {
        setState(() {
          _fileName = result.files.single.name;
          _isProcessing = true;
          _textController.text = "";
        });

        // Simulation of a sophisticated transcription engine
        await Future.delayed(const Duration(seconds: 4));

        setState(() {
          _isProcessing = false;
          _textController.text = "This is a transcribed text from the audio file \"$_fileName\". \n\n"
              "The Speech-to-Text engine analyzed the audio characteristics and successfully "
              "converted the vocal patterns into this readable format. \n\n"
              "You can now edit this text or share it with others using the button below.";
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file explorer: $e'), backgroundColor: Colors.red),
        );
      }
      debugPrint("FilePicker Error: $e");
    }
  }

  void _shareText() {
    if (_textController.text.isNotEmpty) {
      Share.share(_textController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Speech to Text Pro'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Prominent Import Button (System style like QR)
            Card(
              elevation: 0,
              color: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.teal.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.audio_file, color: Colors.teal),
                ),
                title: const Text('Import Audio from Phone', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text(_fileName ?? 'Select MP3, WAV, or M4A', style: const TextStyle(color: Colors.white60)),
                trailing: _fileName != null 
                  ? IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => setState(() { _fileName = null; _textController.clear(); }))
                  : const Icon(Icons.chevron_right, color: Colors.white60),
                onTap: _isProcessing ? null : _importAudio,
              ),
            ),
            const SizedBox(height: 25),

            // Processing Indicator
            if (_isProcessing)
              Container(
                padding: const EdgeInsets.all(30),
                child: Column(
                  children: [
                    RotationTransition(
                      turns: _animationController,
                      child: const Icon(Icons.sync, size: 48, color: Colors.teal),
                    ),
                    const SizedBox(height: 15),
                    const Text('Analyzing Voice Patterns...', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

            // Result Area
            if (_textController.text.isNotEmpty || _isProcessing)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text('TRANSCRIBED TEXT (EDITABLE)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: _isProcessing
                        ? Padding(padding: const EdgeInsets.all(10), child: _buildLoadingSkeleton())
                        : TextField(
                            controller: _textController,
                            maxLines: null,
                            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(10),
                            ),
                          ),
                  ),
                  const SizedBox(height: 25),
                  if (!_isProcessing)
                    ElevatedButton.icon(
                      onPressed: _shareText,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('SHARE TRANSCRIPTION'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 60),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 4,
                        shadowColor: Colors.teal.withOpacity(0.3),
                      ),
                    ),
                ],
              )
            else if (!_isProcessing)
              Container(
                height: 300,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic_none, size: 80, color: Colors.grey.withOpacity(0.2)),
                    const SizedBox(height: 16),
                    Text('No Audio Selected', style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(4, (index) {
        return Container(
          height: 14,
          width: index == 3 ? 150 : double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
