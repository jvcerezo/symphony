import '../../../core/config/links.dart';

/// Links that invite someone into a Jam.
///
/// The shared link is the landing page with the code (`…/?jam=K7M2QX`), so
/// it works for everyone: without Symphony it shows the invite next to the
/// download, with it (on Android) "Open in Symphony" goes to the app link
/// `symphony://jam/K7M2QX`, which joins.
abstract final class JamInvite {
  static const appScheme = 'symphony';

  /// 4 digits (same Wi-Fi) or 6 letters and digits (online), without
  /// look-alikes, as the relay accepts them.
  static final _code = RegExp(r'^(?:\d{4}|[A-HJKMNP-Z2-9]{6})$');

  static bool isCode(String code) => _code.hasMatch(code);

  static Uri webLink(String code) => Uri.parse('${SymphonyLinks.site}/?jam=$code');

  static Uri appLink(String code) => Uri(scheme: appScheme, host: 'jam', path: '/$code');

  /// What the host sends: who's inviting, the link, and the code to type.
  static String message(String code, {required bool online, String? hostName}) {
    final who = hostName == null || hostName.trim().isEmpty ? 'Join my Jam' : '${hostName.trim()} invited you to a Jam';
    final where = online ? '' : ' (on the same Wi-Fi)';
    return '$who on Symphony$where: we hear the same songs at the same time.\n'
        '${webLink(code)}\n'
        'Already have Symphony? Open Jam and enter $code.';
  }

  /// The Jam code in an invite link of either kind, or null.
  static String? codeFrom(Uri uri) {
    String? raw;
    if (uri.scheme == appScheme && uri.host == 'jam') {
      raw = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    } else if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme.isEmpty) {
      raw = uri.queryParameters['jam'];
    }
    final code = raw?.trim().toUpperCase();
    return code != null && isCode(code) ? code : null;
  }
}
