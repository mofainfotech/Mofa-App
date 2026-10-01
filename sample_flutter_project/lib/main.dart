import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'screens/downloads_screen.dart';
import 'screens/main_screen.dart';
import 'screens/quick_share_download_screen.dart';
import 'services/download_manager.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await DownloadManager().init();

  const platform = MethodChannel('com.example.sample_flutter_project/share');
  String? initialSharedText;
  try {
    initialSharedText = await platform.invokeMethod<String>('getSharedData');
  } catch (_) {}

  runApp(
    MultiProvider(
      providers: [
        Provider<bool>.value(value: true),
      ],
      child: MyApp(initialSharedText: initialSharedText),
    ),
  );
}

class MyApp extends StatefulWidget {
  final String? initialSharedText;
  const MyApp({super.key, this.initialSharedText});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const _platform = MethodChannel('com.example.sample_flutter_project/share');
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    // Open Downloads screen when tapping notification
    NotificationService().onNotificationTap = (payload) {
      _openDownloadsScreen();
    };

    NotificationService().getNotificationAppLaunchDetails().then((details) {
      if (details != null && details.didNotificationLaunchApp) {
        _openDownloadsScreen();
      }
    });

    _platform.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments as String?;
        if (text != null && text.isNotEmpty) {
          _handleIncomingUrl(text);
        }
      } else if (call.method == 'onMainLauncher') {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    });
  }

  void _openDownloadsScreen() {
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DownloadsScreen()),
      (route) => false,
    );
  }


  void _handleIncomingUrl(String text) {
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final match = urlRegex.firstMatch(text);
    final url = match != null ? match.group(0)! : text.trim();

    if (url.contains('youtu.be') || url.contains('youtube.com')) {
      _navigatorKey.currentState?.pushAndRemoveUntil(
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) =>
              QuickShareDownloadScreen(videoUrl: url),
        ),
        (route) => false,
      );
    }
  }

  String? _extractYouTubeUrl(String? text) {
    if (text == null || text.isEmpty) return null;
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final match = urlRegex.firstMatch(text);
    final url = match != null ? match.group(0)! : text.trim();
    if (url.contains('youtu.be') || url.contains('youtube.com')) {
      return url;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sharedUrl = _extractYouTubeUrl(widget.initialSharedText);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Mofa',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD0BCFF),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      themeMode: ThemeMode.system,
      // If opened via YouTube share, directly display QuickShareDownloadScreen without ever loading MainScreen!
      home: sharedUrl != null
          ? QuickShareDownloadScreen(videoUrl: sharedUrl)
          : const MainScreen(),
    );
  }
}

