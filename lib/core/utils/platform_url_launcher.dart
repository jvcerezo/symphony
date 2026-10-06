// platform_url_launcher.dart
import 'platform_url_launcher_stub.dart'
    if (dart.library.html) 'platform_url_launcher_web.dart';

Future<bool> platformLaunchUrl(String url, {bool isDownload = false}) =>
    launchCustomUrl(url, isDownload: isDownload);
