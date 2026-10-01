import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PasswordGenScreen extends StatefulWidget {
  const PasswordGenScreen({super.key});

  @override
  State<PasswordGenScreen> createState() => _PasswordGenScreenState();
}

class _PasswordGenScreenState extends State<PasswordGenScreen> {
  double _length = 16;
  bool _useUppercase = true;
  bool _useLowercase = true;
  bool _useNumbers = true;
  bool _useSymbols = true;
  String _customWord = "";
  String _generatedPassword = "";
  final TextEditingController _wordController = TextEditingController();

  void _generatePassword() {
    const String upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const String lower = "abcdefghijklmnopqrstuvwxyz";
    const String numbers = "0123456789";
    const String symbols = r"!@#$%^&*()_+=-[]{};:,.<>?";

    String charPool = "";
    if (_useUppercase) charPool += upper;
    if (_useLowercase) charPool += lower;
    if (_useNumbers) charPool += numbers;
    if (_useSymbols) charPool += symbols;

    if (charPool.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one character type!'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final Random random = Random.secure();
    int targetLength = _length.round();
    
    // Account for custom word length
    int randomPartLength = targetLength - _customWord.length;
    if (randomPartLength < 0) randomPartLength = 0;

    String randomPart = String.fromCharCodes(
      Iterable.generate(randomPartLength, (_) => charPool.codeUnitAt(random.nextInt(charPool.length))),
    );

    // Insert custom word at a random position or at the start
    String finalPass;
    if (_customWord.isNotEmpty) {
      int insertPos = randomPart.isEmpty ? 0 : random.nextInt(randomPart.length + 1);
      finalPass = randomPart.substring(0, insertPos) + _customWord + randomPart.substring(insertPos);
    } else {
      finalPass = randomPart;
    }

    setState(() {
      _generatedPassword = finalPass;
    });
  }

  void _copyToClipboard() {
    if (_generatedPassword.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _generatedPassword));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.indigoAccent,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _generatePassword(); // Generate initial password
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A), // Deep dark background
      appBar: AppBar(
        title: const Text('Password Generator'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Result Card (Glassmorphism look)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade700, Colors.indigo.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.indigo.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10)),
                ],
              ),
              child: Column(
                children: [
                  SelectableText(
                    _generatedPassword,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildActionButton(Icons.refresh, 'Refresh', _generatePassword, Colors.white24, Colors.white),
                      const SizedBox(width: 16),
                      _buildActionButton(Icons.copy, 'Copy', _copyToClipboard, Colors.white, Colors.indigo),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 35),

            _buildSectionHeader('Options'),
            const SizedBox(height: 15),

            // Length Slider Card
            _buildDarkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Password Length', style: TextStyle(color: Colors.white70, fontSize: 16)),
                      Text('${_length.round()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent, fontSize: 22)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.indigoAccent,
                      inactiveTrackColor: Colors.white10,
                      thumbColor: Colors.white,
                      overlayColor: Colors.indigoAccent.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: _length,
                      min: 4,
                      max: 64,
                      divisions: 60,
                      onChanged: (val) {
                        setState(() => _length = val);
                        _generatePassword();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),

            // Options Grid - Fixed childAspectRatio to avoid overflows
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 15,
              crossAxisSpacing: 15,
              childAspectRatio: 2.5, // Increased from 2.2 to prevent overflow on small devices
              children: [
                _buildToggle('Uppercase', _useUppercase, (v) => setState(() { _useUppercase = v; _generatePassword(); })),
                _buildToggle('Lowercase', _useLowercase, (v) => setState(() { _useLowercase = v; _generatePassword(); })),
                _buildToggle('Numbers', _useNumbers, (v) => setState(() { _useNumbers = v; _generatePassword(); })),
                _buildToggle('Symbols', _useSymbols, (v) => setState(() { _useSymbols = v; _generatePassword(); })),
              ],
            ),
            const SizedBox(height: 15),

            // Custom Word Input
            _buildDarkCard(
              child: TextField(
                controller: _wordController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  icon: const Icon(Icons.text_fields, color: Colors.indigoAccent),
                  border: InputBorder.none,
                  hintText: 'Include a custom word...',
                  hintStyle: const TextStyle(color: Colors.white24),
                  labelText: 'Custom Word (Optional)',
                  labelStyle: const TextStyle(color: Colors.white54),
                ),
                onChanged: (val) {
                  setState(() => _customWord = val);
                  _generatePassword();
                },
              ),
            ),
            const SizedBox(height: 40),
            
            // Security Info
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield, size: 18, color: _getStrengthColor()),
                    const SizedBox(width: 10),
                    Text(
                      _getStrengthText(),
                      style: TextStyle(fontWeight: FontWeight.bold, color: _getStrengthColor()),
                    ),
                    const Text(' • Secure Generation', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
    );
  }

  Widget _buildDarkCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E), // Card background
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: child,
    );
  }

  Widget _buildToggle(String title, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(title, 
              style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            )
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              activeColor: Colors.indigoAccent,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onPressed, Color bg, Color fg) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 0,
      ),
    );
  }

  Color _getStrengthColor() {
    if (_length < 8) return Colors.redAccent;
    if (_length < 16) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  String _getStrengthText() {
    if (_length < 8) return 'WEAK';
    if (_length < 16) return 'MODERATE';
    return 'STRONG';
  }
}
