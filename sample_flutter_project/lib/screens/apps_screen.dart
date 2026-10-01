import 'package:flutter/material.dart';
import '../widgets/custom_card.dart';
import '../tools/tool_screens.dart';

class AppsScreen extends StatelessWidget {
  const AppsScreen({super.key});

  final List<Map<String, dynamic>> tools = const [
    {'title': 'YT Downloader', 'icon': Icons.ondemand_video, 'desc': 'Video & Playlist', 'widget': YTDownloaderScreen()},
    {'title': 'QR Generator', 'icon': Icons.qr_code_2, 'desc': 'Create QR codes', 'widget': QRGeneratorScreen()},
    {'title': 'Text to Speech', 'icon': Icons.record_voice_over, 'desc': 'Read text aloud', 'widget': TtsScreen()},
    {'title': 'Speech to Text', 'icon': Icons.mic, 'desc': 'Convert audio to text', 'widget': SttScreen()},
    {'title': 'Video to MP3', 'icon': Icons.audiotrack, 'desc': 'Extract audio', 'widget': VideoToMp3Screen()},
    {'title': 'Password Gen', 'icon': Icons.password, 'desc': 'Secure passwords', 'widget': PasswordGenScreen()},
    {'title': 'Image Enhancer', 'icon': Icons.auto_awesome, 'desc': 'Upscale & Enhance', 'widget': ImageEnhancerScreen()},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Tools & Utilities'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.8, // Reduced from 0.85 to allow more height
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: tools.length,
        itemBuilder: (context, index) {
          final tool = tools[index];
          return CustomCard(
            title: tool['title'],
            subtitle: tool['desc'],
            icon: tool['icon'],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => tool['widget'] as Widget),
              );
            },
          );
        },
      ),
    );
  }
}
