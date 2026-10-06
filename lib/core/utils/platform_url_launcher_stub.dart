// platform_url_launcher_stub.dart
import 'package:url_launcher/url_launcher.dart';

Future<bool> launchCustomUrl(String url, {bool isDownload = false}) async {
  final uri = Uri.parse(url);
  return await launchUrl(uri, mode: LaunchMode.externalApplication);
}
