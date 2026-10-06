// platform_url_launcher_web.dart
import 'dart:html' as html;

Future<bool> launchCustomUrl(String url, {bool isDownload = false}) async {
  try {
    Uri uri = Uri.parse(url);
    if (!uri.hasScheme) {
      uri = Uri.base.resolve(url);
    }
    final resolved = uri.toString();

    final isFile = isDownload ||
        resolved.endsWith('.apk') ||
        resolved.endsWith('.zip') ||
        resolved.endsWith('.exe') ||
        resolved.contains('/releases/download/');

    if (isFile) {
      // Use hidden anchor element with download attribute
      final anchor = html.AnchorElement(href: resolved);
      anchor.setAttribute('download', '');
      anchor.style.display = 'none';
      html.document.body?.children.add(anchor);
      anchor.click();
      anchor.remove();
      return true;
    } else {
      // Normal external web page navigation
      html.window.open(resolved, '_blank');
      return true;
    }
  } catch (e) {
    html.window.location.href = url;
    return true;
  }
}
