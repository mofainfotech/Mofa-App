import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

class QRGeneratorScreen extends StatefulWidget {
  const QRGeneratorScreen({super.key});

  @override
  State<QRGeneratorScreen> createState() => _QRGeneratorScreenState();
}

class _QRGeneratorScreenState extends State<QRGeneratorScreen> {
  final TextEditingController _textController = TextEditingController(text: 'https://google.com');
  Color _qrColor = Colors.black;
  Color _bgColor = Colors.white;
  File? _logoFile;
  QrDataModuleShape _dataShape = QrDataModuleShape.square;
  QrEyeShape _eyeShape = QrEyeShape.square;
  final GlobalKey _qrKey = GlobalKey();

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
      );
      
      if (pickedFile != null) {
        setState(() {
          _logoFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open gallery: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveQrCode() async {
    try {
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        final tempDir = await getTemporaryDirectory();
        final file = await File('${tempDir.path}/qr_code.png').create();
        await file.writeAsBytes(bytes);
        
        await Gal.putImage(file.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved to Gallery!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Code Pro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _saveQrCode,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Preview
            RepaintBoundary(
              key: _qrKey,
              child: Container(
                color: _bgColor,
                padding: const EdgeInsets.all(20),
                child: QrImageView(
                  data: _textController.text,
                  version: QrVersions.auto,
                  size: 250.0,
                  gapless: false,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  eyeStyle: QrEyeStyle(
                    eyeShape: _eyeShape,
                    color: _qrColor,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: _dataShape,
                    color: _qrColor,
                  ),
                  embeddedImage: _logoFile != null ? FileImage(_logoFile!) : null,
                  embeddedImageStyle: const QrEmbeddedImageStyle(
                    size: Size(50, 50),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            
            // Text Input
            TextField(
              controller: _textController,
              onChanged: (val) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'URL or Text',
                hintText: 'Enter https://...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                prefixIcon: const Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 20),

            // Customization Options
            ExpansionTile(
              leading: const Icon(Icons.palette),
              title: const Text('Customize Colors'),
              children: [
                ListTile(
                  title: const Text('QR Color'),
                  trailing: CircleAvatar(backgroundColor: _qrColor, radius: 15),
                  onTap: () => _showColorPicker(true),
                ),
                ListTile(
                  title: const Text('Background Color'),
                  trailing: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _bgColor,
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                  ),
                  onTap: () => _showColorPicker(false),
                ),
                SwitchListTile(
                  title: const Text('Transparent Background'),
                  value: _bgColor == Colors.transparent,
                  onChanged: (val) {
                    setState(() {
                      _bgColor = val ? Colors.transparent : Colors.white;
                    });
                  },
                ),
              ],
            ),

            ExpansionTile(
              leading: const Icon(Icons.shape_line),
              title: const Text('Shapes & Style'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      const Text('Data Pattern'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _shapeButton('Square', QrDataModuleShape.square, true),
                          _shapeButton('Circle', QrDataModuleShape.circle, true),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text('Eye Style'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _shapeButton('Square', QrEyeShape.square, false),
                          _shapeButton('Circle', QrEyeShape.circle, false),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            ListTile(
              leading: const Icon(Icons.add_photo_alternate),
              title: const Text('Add Center Logo'),
              subtitle: Text(_logoFile != null ? 'Logo Selected' : 'No Logo'),
              trailing: _logoFile != null 
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _logoFile = null))
                : null,
              onTap: _pickLogo,
            ),
            
            const SizedBox(height: 40),
            
            ElevatedButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Download QR Code'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: _saveQrCode,
            ),
          ],
        ),
      ),
    );
  }

  Widget _shapeButton(String label, dynamic value, bool isData) {
    bool selected = isData ? _dataShape == value : _eyeShape == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (val) {
        setState(() {
          if (isData) _dataShape = value; else _eyeShape = value;
        });
      },
    );
  }

  void _showColorPicker(bool isQr) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: isQr ? _qrColor : _bgColor,
            onColorChanged: (color) {
              setState(() {
                if (isQr) _qrColor = color; else _bgColor = color;
              });
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }
}
