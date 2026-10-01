import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _textController = TextEditingController(
    text: "Hello! This is a professional text to speech generator. Type anything here and listen to the magic.",
  );

  final List<Map<String, String>> _allVoices = [];
  Map<String, String>? _currentVoice;
  double _pitch = 1.0;
  double _speed = 0.5;
  double _volumeBoost = 50.0; // 1 to 100 scale
  String _gender = 'Female';
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      final voices = await _flutterTts.getVoices;
      _allVoices.clear(); // Ensure clean list
      _allVoices.addAll(List<Map<String, String>>.from(
        voices.map((v) => Map<String, String>.from(v))
      ));
      
      _updateVoice();
    } catch (e) {
      debugPrint("TTS Init Error: $e");
    }

    _flutterTts.setStartHandler(() => setState(() => _isPlaying = true));
    _flutterTts.setCompletionHandler(() => setState(() => _isPlaying = false));
    _flutterTts.setErrorHandler((msg) => setState(() => _isPlaying = false));
  }

  void _updateVoice() {
    if (_allVoices.isEmpty) return;
    
    final bool isMale = _gender == 'Male';
    
    // 1. Try explicit keyword match
    var filtered = _allVoices.where((v) {
      final name = v['name']!.toLowerCase();
      if (isMale) {
        return name.contains('male') || name.contains('iom') || name.contains('dfz') || name.contains('mdy');
      } else {
        return name.contains('female') || name.contains('sfg') || name.contains('fmn') || name.contains('wnt');
      }
    }).toList();

    // 2. Fallback to locale-based search if gender-specific not found
    if (filtered.isEmpty) {
       filtered = _allVoices.where((v) => v['locale']!.startsWith('en')).toList();
    }
    
    setState(() {
      _currentVoice = filtered.isNotEmpty ? filtered.first : _allVoices.first;
      if (_currentVoice != null) {
        _flutterTts.setVoice(_currentVoice!);
        debugPrint("Selected Voice: ${_currentVoice!['name']} - ${_currentVoice!['locale']}");
      }
    });
  }

  Future<void> _speak() async {
    if (_textController.text.trim().isEmpty) return;

    await _flutterTts.setVolume(_volumeBoost / 100.0);
    await _flutterTts.setPitch(_pitch);
    await _flutterTts.setSpeechRate(_speed);
    if (_currentVoice != null) await _flutterTts.setVoice(_currentVoice!);
    
    await _flutterTts.speak(_textController.text);
  }

  Future<void> _stop() async {
    await _flutterTts.stop();
    setState(() => _isPlaying = false);
  }

  Future<void> _saveMp3() async {
    if (_textController.text.trim().isEmpty) return;

    // Show persistent loading message
    final loadingSnackBar = ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 15),
            Text('Synthesizing MP3...'),
          ],
        ),
        duration: Duration(days: 1), // Persistent until dismissed
      ),
    );

    try {
      final fileName = "tts_${DateTime.now().millisecondsSinceEpoch}.mp3";
      await _flutterTts.setVolume(_volumeBoost / 100.0);
      await _flutterTts.setPitch(_pitch);
      await _flutterTts.setSpeechRate(_speed);
      if (_currentVoice != null) await _flutterTts.setVoice(_currentVoice!);

      final result = await _flutterTts.synthesizeToFile(_textController.text, fileName);
      
      // Ensure the loading message was actually seen for a split second for UX
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars(); 

      if (result == 1) {
        final dir = await getExternalStorageDirectory();
        final file = File("${dir!.path}/$fileName");
        
        if (await file.exists()) {
           final publicDir = Directory('/storage/emulated/0/Download/mofa_tts');
           if (!await publicDir.exists()) await publicDir.create(recursive: true);
           await file.copy("${publicDir.path}/$fileName");
           
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 backgroundColor: Colors.green.shade800,
                 behavior: SnackBarBehavior.floating,
                 duration: const Duration(seconds: 8), // Much longer duration
                 action: SnackBarAction(
                   label: 'OK',
                   textColor: Colors.white,
                   onPressed: () {},
                 ),
                 content: const Row(
                   children: [
                     Icon(Icons.check_circle, color: Colors.white),
                     SizedBox(width: 10),
                     Expanded(child: Text('MP3 Saved Successfully')),
                   ],
                 ),
               ),
             );
           }
        }
      } else {
        throw "Synthesis failed.";
      }
    } catch (e) {
       ScaffoldMessenger.of(context).removeCurrentSnackBar();
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Save error: $e'), backgroundColor: Colors.red)
         );
       }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Text to Speech'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Text Area (Black/White as requested)
            Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: TextField(
                controller: _textController,
                maxLines: 8,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: "Type text here...",
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(20),
                ),
              ),
            ),
            const SizedBox(height: 25),

            // Gender Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _genderBtn('Male', Icons.male),
                const SizedBox(width: 15),
                _genderBtn('Female', Icons.female),
              ],
            ),
            const SizedBox(height: 30),

            // Sliders
            _sliderGroup("Pitch", _pitch, (v) => setState(() => _pitch = v), 0.5, 2.0),
            _sliderGroup("Speed", _speed, (v) => setState(() => _speed = v), 0.0, 1.0),
            _sliderGroup("Volume Boost", _volumeBoost, (v) => setState(() => _volumeBoost = v), 1.0, 100.0, true),
            
            const SizedBox(height: 40),

            // Buttons
            ElevatedButton.icon(
              onPressed: _isPlaying ? _stop : _speak,
              icon: Icon(_isPlaying ? Icons.stop : Icons.campaign),
              label: Text(_isPlaying ? "Stop" : "Speak Now"),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isPlaying ? Colors.red : Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: _saveMp3,
              icon: const Icon(Icons.download),
              label: const Text("Save MP3"),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.indigoAccent),
                foregroundColor: Colors.indigoAccent,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _genderBtn(String g, IconData icon) {
    bool sel = _gender == g;
    return GestureDetector(
      onTap: () { setState(() => _gender = g); _updateVoice(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? Colors.indigoAccent : const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: sel ? Colors.indigoAccent : Colors.white10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(g, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _sliderGroup(String label, double val, Function(double) onChanged, double min, double max, [bool isInt = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
              Text(isInt ? val.toInt().toString() : val.toStringAsFixed(2), 
                style: const TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.indigoAccent,
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: val,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
