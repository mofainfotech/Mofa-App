import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DownloadManager {
  static Future<bool> downloadFile(String url, String fileName) async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return false;

      final filePath = "${directory.path}/$fileName";
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
