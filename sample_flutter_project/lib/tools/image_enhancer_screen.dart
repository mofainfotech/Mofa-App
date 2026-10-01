import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

enum EnhancePreset {
  auto,
  superRes2x,
  superRes4x,
  clarity,
  hdr,
  portrait,
  night,
  monochrome,
  custom,
}

class EnhanceConfig {
  final Uint8List inputBytes;
  final int scale;
  final double sharpness;
  final double brightness;
  final double contrast;
  final double saturation;
  final double gamma;
  final bool portraitSmooth;
  final bool isMonochrome;
  final int outputQuality;

  EnhanceConfig({
    required this.inputBytes,
    this.scale = 1,
    this.sharpness = 0.35,
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.gamma = 1.0,
    this.portraitSmooth = false,
    this.isMonochrome = false,
    this.outputQuality = 92,
  });
}

class EnhanceResult {
  final Uint8List outputBytes;
  final int width;
  final int height;
  final int originalWidth;
  final int originalHeight;
  final int processTimeMs;

  EnhanceResult({
    required this.outputBytes,
    required this.width,
    required this.height,
    required this.originalWidth,
    required this.originalHeight,
    required this.processTimeMs,
  });
}

/// Standalone top-level worker for compute isolate execution
EnhanceResult _processImageWorker(EnhanceConfig config) {
  final stopwatch = Stopwatch()..start();
  final decoded = img.decodeImage(config.inputBytes);
  if (decoded == null) {
    throw Exception('Failed to decode image data.');
  }

  final origW = decoded.width;
  final origH = decoded.height;

  img.Image processed = decoded;

  // 1. Super-Resolution / Bicubic Upscaling
  if (config.scale > 1) {
    final targetW = origW * config.scale;
    final targetH = origH * config.scale;

    // Guard against excessive memory usage on mobile devices (cap at 4096px)
    final double safeScale = (targetW > 4096 || targetH > 4096)
        ? (4096.0 / (targetW > targetH ? targetW : targetH))
        : 1.0;

    processed = img.copyResize(
      processed,
      width: (targetW * safeScale).round(),
      height: (targetH * safeScale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  // 2. Soft skin smoothing for portraits
  if (config.portraitSmooth) {
    processed = img.gaussianBlur(processed, radius: 1);
  }

  // 3. Monochrome conversion if selected
  if (config.isMonochrome) {
    processed = img.grayscale(processed);
  }

  // 4. Color adjustments (brightness, contrast, saturation, gamma)
  if (config.brightness != 1.0 ||
      config.contrast != 1.0 ||
      config.saturation != 1.0 ||
      config.gamma != 1.0) {
    processed = img.adjustColor(
      processed,
      brightness: config.brightness,
      contrast: config.contrast,
      saturation: config.isMonochrome ? 0.0 : config.saturation,
      gamma: config.gamma,
    );
  }

  // 5. Adaptive unsharp masking convolution kernel for crisp edges and textures
  if (config.sharpness > 0.01) {
    final k = config.sharpness * 0.9;
    final center = 1.0 + (4.0 * k);
    final edge = -k;
    final filter = <num>[
      0.0, edge, 0.0,
      edge, center, edge,
      0.0, edge, 0.0,
    ];

    processed = img.convolution(
      processed,
      filter: filter,
      div: 1,
      offset: 0,
    );
  }

  final outputBytes = Uint8List.fromList(img.encodeJpg(processed, quality: config.outputQuality));
  stopwatch.stop();

  return EnhanceResult(
    outputBytes: outputBytes,
    width: processed.width,
    height: processed.height,
    originalWidth: origW,
    originalHeight: origH,
    processTimeMs: stopwatch.elapsedMilliseconds,
  );
}

class ImageEnhancerScreen extends StatefulWidget {
  const ImageEnhancerScreen({super.key});

  @override
  State<ImageEnhancerScreen> createState() => _ImageEnhancerScreenState();
}

class _ImageEnhancerScreenState extends State<ImageEnhancerScreen> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _originalBytes;
  String? _imageFileName;
  int? _originalSize;

  EnhanceResult? _enhancedResult;
  bool _isProcessing = false;
  String _processingStep = 'Enhancing image...';

  // Preset & Configuration
  EnhancePreset _currentPreset = EnhancePreset.auto;
  double _sharpness = 0.40;
  double _brightness = 1.05;
  double _contrast = 1.15;
  double _saturation = 1.15;
  double _gamma = 1.0;
  int _scale = 1;
  bool _portraitSmooth = false;
  bool _isMonochrome = false;

  // Comparison UI state
  double _splitPosition = 0.5; // 0.0 = all original, 1.0 = all enhanced
  bool _forceOriginal = false; // When touch & hold
  bool _isSideBySide = false;

  // Fine tune drawer/panel
  bool _showFineTuning = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final size = await pickedFile.length();
        setState(() {
          _originalBytes = bytes;
          _imageFileName = pickedFile.name;
          _originalSize = size;
          _enhancedResult = null;
        });
        _applyPreset(_currentPreset);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final size = await file.length();
        setState(() {
          _originalBytes = bytes;
          _imageFileName = result.files.single.name;
          _originalSize = size;
          _enhancedResult = null;
        });
        _applyPreset(_currentPreset);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyPreset(EnhancePreset preset) {
    setState(() {
      _currentPreset = preset;
    });

    switch (preset) {
      case EnhancePreset.auto:
        _sharpness = 0.40;
        _brightness = 1.05;
        _contrast = 1.15;
        _saturation = 1.15;
        _gamma = 1.0;
        _scale = 1;
        _portraitSmooth = false;
        _isMonochrome = false;
        break;
      case EnhancePreset.superRes2x:
        _sharpness = 0.50;
        _brightness = 1.02;
        _contrast = 1.10;
        _saturation = 1.05;
        _gamma = 1.0;
        _scale = 2;
        _portraitSmooth = false;
        _isMonochrome = false;
        break;
      case EnhancePreset.superRes4x:
        _sharpness = 0.60;
        _brightness = 1.02;
        _contrast = 1.10;
        _saturation = 1.05;
        _gamma = 1.0;
        _scale = 4;
        _portraitSmooth = false;
        _isMonochrome = false;
        break;
      case EnhancePreset.clarity:
        _sharpness = 0.75;
        _brightness = 1.02;
        _contrast = 1.25;
        _saturation = 1.10;
        _gamma = 1.0;
        _scale = 1;
        _portraitSmooth = false;
        _isMonochrome = false;
        break;
      case EnhancePreset.hdr:
        _sharpness = 0.35;
        _brightness = 1.08;
        _contrast = 1.25;
        _saturation = 1.35;
        _gamma = 1.05;
        _scale = 1;
        _portraitSmooth = false;
        _isMonochrome = false;
        break;
      case EnhancePreset.portrait:
        _sharpness = 0.25;
        _brightness = 1.08;
        _contrast = 1.08;
        _saturation = 1.08;
        _gamma = 1.02;
        _scale = 1;
        _portraitSmooth = true;
        _isMonochrome = false;
        break;
      case EnhancePreset.night:
        _sharpness = 0.35;
        _brightness = 1.28;
        _contrast = 1.15;
        _saturation = 1.10;
        _gamma = 1.25;
        _scale = 1;
        _portraitSmooth = false;
        _isMonochrome = false;
        break;
      case EnhancePreset.monochrome:
        _sharpness = 0.55;
        _brightness = 1.05;
        _contrast = 1.35;
        _saturation = 0.0;
        _gamma = 1.0;
        _scale = 1;
        _portraitSmooth = false;
        _isMonochrome = true;
        break;
      case EnhancePreset.custom:
        break;
    }

    _runEnhancement();
  }

  Future<void> _runEnhancement() async {
    if (_originalBytes == null) return;

    setState(() {
      _isProcessing = true;
      _processingStep = _scale > 1
          ? 'Performing ${_scale}x Super-Resolution & Sharpening...'
          : 'Processing details & color balance...';
    });

    final config = EnhanceConfig(
      inputBytes: _originalBytes!,
      scale: _scale,
      sharpness: _sharpness,
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
      gamma: _gamma,
      portraitSmooth: _portraitSmooth,
      isMonochrome: _isMonochrome,
    );

    try {
      // Execute in background isolate so UI remains 60fps responsive
      final result = await compute(_processImageWorker, config);

      if (mounted) {
        setState(() {
          _enhancedResult = result;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enhancement error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveToGallery() async {
    if (_enhancedResult == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/enhanced_$timeStamp.jpg');
      await tempFile.writeAsBytes(_enhancedResult!.outputBytes);

      // Save to device photo gallery
      await Gal.putImage(tempFile.path);

      // Also copy to public Downloads/mofa_enhanced folder for easy file manager access
      try {
        final publicDir = Directory('/storage/emulated/0/Download/mofa_enhanced');
        if (!await publicDir.exists()) {
          await publicDir.create(recursive: true);
        }
        final destPath = '${publicDir.path}/enhanced_$timeStamp.jpg';
        await tempFile.copy(destPath);
      } catch (_) {
        // Fallback for non-Android or restricted systems
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saved to Gallery & Downloads/mofa_enhanced!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _shareImage() async {
    if (_enhancedResult == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final timeStamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/enhanced_$timeStamp.jpg');
      await file.writeAsBytes(_enhancedResult!.outputBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Enhanced photo (${_enhancedResult!.width}x${_enhancedResult!.height})',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Image Enhancer'),
            if (_imageFileName != null)
              Text(
                _imageFileName!,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_originalBytes != null) ...[
            IconButton(
              icon: Icon(_isSideBySide ? Icons.view_agenda : Icons.compare),
              tooltip: _isSideBySide ? 'Slider Mode' : 'Side by Side Mode',
              onPressed: () => setState(() => _isSideBySide = !_isSideBySide),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset to Original',
              onPressed: () {
                setState(() {
                  _enhancedResult = null;
                  _applyPreset(EnhancePreset.auto);
                });
              },
            ),
          ],
        ],
      ),
      body: _originalBytes == null ? _buildPickArea() : _buildWorkspace(),
      bottomNavigationBar: _originalBytes != null ? _buildBottomActions() : null,
    );
  }

  /// Initial screen before image is picked
  Widget _buildPickArea() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Hero card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade900, Colors.indigo.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.purple.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, size: 54, color: Colors.cyanAccent),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'AI Image Enhancer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '100% On-Device • Zero API Keys • Super Clear',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.offline_bolt, color: Colors.cyanAccent, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'No Sign-up • No Data Uploads • Completely Private',
                          style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Pick buttons
            Row(
              children: [
                Expanded(
                  child: _buildActionTile(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    color: Colors.indigoAccent,
                    onTap: () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionTile(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    color: Colors.purpleAccent,
                    onTap: () => _pickImage(ImageSource.camera),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildActionTile(
              icon: Icons.folder_open,
              label: 'Browse Files',
              color: Colors.tealAccent,
              onTap: _pickFile,
            ),

            const SizedBox(height: 36),
            // Feature Highlights
            _buildFeatureBadge(Icons.hd, '2x & 4x Super-Resolution bicubic upscaling'),
            _buildFeatureBadge(Icons.filter_vintage, 'Unsharp Mask high-frequency detail recovery'),
            _buildFeatureBadge(Icons.hdr_on, 'Vibrant HDR tone-mapping & color pop'),
            _buildFeatureBadge(Icons.face_retouching_natural, 'Portrait smoothing & low-light night sight'),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent.withValues(alpha: 0.8), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Main workspace when image is loaded
  Widget _buildWorkspace() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image Comparison View
          _buildComparisonSection(),

          const SizedBox(height: 16),

          // Resolution / Stats Banner
          _buildStatsBanner(),

          const SizedBox(height: 16),

          // Preset Selection Strip
          _buildPresetSelector(),

          const SizedBox(height: 16),

          // Fine Tuning Collapsible
          _buildFineTuningSection(),
        ],
      ),
    );
  }

  /// Before/After Interactive Comparison
  Widget _buildComparisonSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 320,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_isSideBySide)
            _buildSideBySideView()
          else
            _buildSplitSliderView(),

          // Loading overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.cyanAccent),
                    const SizedBox(height: 16),
                    Text(
                      _processingStep,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // "Hold to View Original" Button at bottom
          if (_enhancedResult != null && !_isProcessing && !_isSideBySide)
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTapDown: (_) => setState(() => _forceOriginal = true),
                onTapUp: (_) => setState(() => _forceOriginal = false),
                onTapCancel: () => setState(() => _forceOriginal = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _forceOriginal ? Icons.visibility : Icons.touch_app,
                        color: Colors.cyanAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _forceOriginal ? 'Showing Original' : 'Hold for Original',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSplitSliderView() {
    final activeEnhancedBytes = _forceOriginal
        ? _originalBytes!
        : (_enhancedResult?.outputBytes ?? _originalBytes!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final totalHeight = constraints.maxHeight;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _splitPosition = (_splitPosition + details.delta.dx / totalWidth).clamp(0.05, 0.95);
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Bottom layer: Enhanced image
              Image.memory(
                activeEnhancedBytes,
                fit: BoxFit.contain,
                width: totalWidth,
                height: totalHeight,
              ),

              // Top layer: Original image clipped to split position
              if (_enhancedResult != null && !_forceOriginal)
                ClipRect(
                  clipper: _SplitClipper(_splitPosition * totalWidth),
                  child: Image.memory(
                    _originalBytes!,
                    fit: BoxFit.contain,
                    width: totalWidth,
                    height: totalHeight,
                  ),
                ),

              // Divider Line & Drag Handle
              if (_enhancedResult != null && !_forceOriginal)
                Positioned(
                  left: (_splitPosition * totalWidth) - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: Colors.cyanAccent,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.compare_arrows, size: 20, color: Colors.black),
                      ),
                    ),
                  ),
                ),

              // Labels on top
              if (_enhancedResult != null && !_forceOriginal) ...[
                Positioned(
                  top: 12,
                  left: 12,
                  child: _buildBadge('BEFORE', Colors.grey.shade800),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildBadge('ENHANCED', Colors.cyan.shade900),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSideBySideView() {
    return Row(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(_originalBytes!, fit: BoxFit.contain),
              Positioned(top: 8, left: 8, child: _buildBadge('ORIGINAL', Colors.grey.shade900)),
            ],
          ),
        ),
        Container(width: 2, color: Colors.white.withValues(alpha: 0.2)),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                _enhancedResult?.outputBytes ?? _originalBytes!,
                fit: BoxFit.contain,
              ),
              Positioned(top: 8, right: 8, child: _buildBadge('ENHANCED', Colors.cyan.shade900)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Resolution and size comparison card
  Widget _buildStatsBanner() {
    if (_enhancedResult == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white60, size: 18),
            const SizedBox(width: 8),
            Text(
              'Select a preset below to enhance this image',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
        ),
      );
    }

    final origW = _enhancedResult!.originalWidth;
    final origH = _enhancedResult!.originalHeight;
    final enhW = _enhancedResult!.width;
    final enhH = _enhancedResult!.height;
    final origSize = _originalSize ?? _originalBytes!.length;
    final enhSize = _enhancedResult!.outputBytes.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('Original', '$origW × $origH', _formatBytes(origSize), Colors.white70),
          Container(height: 36, width: 1, color: Colors.white.withValues(alpha: 0.1)),
          const Icon(Icons.arrow_forward, color: Colors.cyanAccent, size: 20),
          Container(height: 36, width: 1, color: Colors.white.withValues(alpha: 0.1)),
          _buildStatColumn('Enhanced', '$enhW × $enhH', _formatBytes(enhSize), Colors.cyanAccent),
          Container(height: 36, width: 1, color: Colors.white.withValues(alpha: 0.1)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Speed', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
              const SizedBox(height: 2),
              Text(
                '${_enhancedResult!.processTimeMs} ms',
                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String title, String res, String size, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          res,
          style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          size,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
        ),
      ],
    );
  }

  /// Preset selector chips
  Widget _buildPresetSelector() {
    final presets = [
      {'preset': EnhancePreset.auto, 'label': 'Auto Magic', 'icon': Icons.auto_awesome},
      {'preset': EnhancePreset.superRes2x, 'label': '2x Upscale', 'icon': Icons.zoom_in},
      {'preset': EnhancePreset.superRes4x, 'label': '4x Ultra', 'icon': Icons.filter_center_focus},
      {'preset': EnhancePreset.clarity, 'label': 'HD Clarity', 'icon': Icons.high_quality},
      {'preset': EnhancePreset.hdr, 'label': 'HDR Vivid', 'icon': Icons.hdr_on},
      {'preset': EnhancePreset.portrait, 'label': 'Portrait', 'icon': Icons.face_retouching_natural},
      {'preset': EnhancePreset.night, 'label': 'Night Sight', 'icon': Icons.nights_stay},
      {'preset': EnhancePreset.monochrome, 'label': 'B&W Art', 'icon': Icons.monochrome_photos},
      {'preset': EnhancePreset.custom, 'label': 'Custom', 'icon': Icons.tune},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Enhancement Modes',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                '100% Offline Engine',
                style: TextStyle(color: Colors.cyanAccent.withValues(alpha: 0.8), fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = presets[index];
              final preset = item['preset'] as EnhancePreset;
              final isSelected = _currentPreset == preset;

              return ChoiceChip(
                showCheckmark: false,
                avatar: Icon(
                  item['icon'] as IconData,
                  size: 16,
                  color: isSelected ? Colors.black : Colors.cyanAccent,
                ),
                label: Text(
                  item['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
                selected: isSelected,
                selectedColor: Colors.cyanAccent,
                backgroundColor: const Color(0xFF1E1E2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? Colors.cyanAccent : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                onSelected: (val) {
                  if (val) {
                    if (preset == EnhancePreset.custom) {
                      setState(() {
                        _currentPreset = EnhancePreset.custom;
                        _showFineTuning = true;
                      });
                    } else {
                      _applyPreset(preset);
                    }
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Fine tuning sliders for Custom mode
  Widget _buildFineTuningSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ExpansionTile(
        initiallyExpanded: _showFineTuning,
        onExpansionChanged: (exp) => setState(() => _showFineTuning = exp),
        leading: const Icon(Icons.tune, color: Colors.cyanAccent),
        title: const Text(
          'Pro Manual Adjustments',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          'Fine tune sharpness, contrast, exposure & scale',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Upscale Scale selector
          Row(
            children: [
              const Text('Upscale Resolution: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              _buildScaleOption(1, '1x (Original)'),
              const SizedBox(width: 8),
              _buildScaleOption(2, '2x (Super Res)'),
              const SizedBox(width: 8),
              _buildScaleOption(4, '4x (Ultra HD)'),
            ],
          ),
          const SizedBox(height: 12),

          // Sharpness Slider
          _buildSliderRow(
            label: 'Sharpness',
            icon: Icons.details,
            value: _sharpness,
            min: 0.0,
            max: 1.0,
            display: '${(_sharpness * 100).toInt()}%',
            onChanged: (val) => setState(() {
              _sharpness = val;
              _currentPreset = EnhancePreset.custom;
            }),
          ),

          // Contrast Slider
          _buildSliderRow(
            label: 'Contrast',
            icon: Icons.contrast,
            value: _contrast,
            min: 0.6,
            max: 1.8,
            display: '${((_contrast - 1.0) * 100).toStringAsFixed(0)}%',
            onChanged: (val) => setState(() {
              _contrast = val;
              _currentPreset = EnhancePreset.custom;
            }),
          ),

          // Brightness Slider
          _buildSliderRow(
            label: 'Brightness',
            icon: Icons.brightness_6,
            value: _brightness,
            min: 0.6,
            max: 1.6,
            display: '${((_brightness - 1.0) * 100).toStringAsFixed(0)}%',
            onChanged: (val) => setState(() {
              _brightness = val;
              _currentPreset = EnhancePreset.custom;
            }),
          ),

          // Saturation Slider
          _buildSliderRow(
            label: 'Saturation / Vibrance',
            icon: Icons.palette,
            value: _saturation,
            min: 0.0,
            max: 2.0,
            display: '${((_saturation - 1.0) * 100).toStringAsFixed(0)}%',
            onChanged: (val) => setState(() {
              _saturation = val;
              _currentPreset = EnhancePreset.custom;
            }),
          ),

          const SizedBox(height: 8),

          ElevatedButton.icon(
            icon: const Icon(Icons.flash_on),
            label: const Text('Apply Manual Adjustments'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _runEnhancement,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildScaleOption(int scale, String label) {
    final isSelected = _scale == scale;
    return ChoiceChip(
      showCheckmark: false,
      label: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontSize: 11)),
      selected: isSelected,
      selectedColor: Colors.cyanAccent,
      backgroundColor: const Color(0xFF0F0F1A),
      onSelected: (val) {
        if (val) {
          setState(() {
            _scale = scale;
            _currentPreset = EnhancePreset.custom;
          });
          _runEnhancement();
        }
      },
    );
  }

  Widget _buildSliderRow({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            Text(display, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.cyanAccent,
            thumbColor: Colors.cyanAccent,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            overlayColor: Colors.cyanAccent.withValues(alpha: 0.2),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// Bottom action bar: Save to gallery, Share, Choose another photo
  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Pick another photo button
            IconButton(
              icon: const Icon(Icons.add_photo_alternate, color: Colors.white70),
              tooltip: 'Choose another photo',
              onPressed: () => _pickImage(ImageSource.gallery),
            ),
            const SizedBox(width: 8),

            // Share Button
            OutlinedButton.icon(
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onPressed: _enhancedResult != null ? _shareImage : null,
            ),
            const SizedBox(width: 12),

            // Save to Gallery Button
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Save to Gallery', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _enhancedResult != null ? _saveToGallery : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom clipper to show before/after split
class _SplitClipper extends CustomClipper<Rect> {
  final double splitX;
  _SplitClipper(this.splitX);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, splitX, size.height);
  }

  @override
  bool shouldReclip(_SplitClipper oldClipper) => oldClipper.splitX != splitX;
}
