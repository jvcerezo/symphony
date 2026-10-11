import 'package:flutter/foundation.dart';

/// Where the client looks for the Symphony backend (`server.dart`).
///
/// Single source of truth for server origins; services must not hardcode
/// hosts. Resolution order for [candidateOrigins]:
///
/// 1. `--dart-define=SYMPHONY_SERVER=https://host[:port]` when provided.
/// 2. Web: the page's own origin (the web build is served by `server.dart`).
///
/// Native builds get no default origins: Windows and Android are fully
/// self-sufficient and never depend on a Symphony server.
abstract final class ServerConfig {
  /// Production backend (`server.dart` behind the Cloudflare tunnel). The bare
  /// `symphony.` host is the static landing page on GitHub Pages.
  static const String productionOrigin = 'https://symphony-api.jettimothycerezo.dev';

  /// Value of `--dart-define=SYMPHONY_SERVER=…` (empty when not set).
  static const String overrideOrigin = String.fromEnvironment('SYMPHONY_SERVER');

  /// Ordered, de-duplicated list of origins to try.
  ///
  /// The optional parameters exist for tests; production code calls this
  /// with no arguments.
  static List<String> candidateOrigins({
    bool? isWeb,
    String? webOrigin,
    String? override,
  }) {
    final web = isWeb ?? kIsWeb;
    final forced = _normalize(override ?? overrideOrigin);

    final origins = <String>[];
    void add(String? origin) {
      if (origin != null && origin.isNotEmpty && !origins.contains(origin)) {
        origins.add(origin);
      }
    }

    add(forced);
    if (web) {
      add(webOrigin ?? _pageOrigin());
      return origins;
    }

    // Native apps resolve, play and store everything on the device. They only
    // talk to a Symphony server when one is explicitly set at build time.
    return origins;
  }

  /// The single origin used for endpoints that are not retried across hosts
  /// (offline downloads, streaming proxy URLs).
  static String primaryOrigin({bool? isWeb, String? webOrigin, String? override}) {
    final forced = _normalize(override ?? overrideOrigin);
    if (forced != null) return forced;
    if (isWeb ?? kIsWeb) {
      final page = webOrigin ?? _pageOrigin();
      if (page != null && page.isNotEmpty) return page;
    }
    return productionOrigin;
  }

  /// True when [host] is one of our own backends, so requests to it must not
  /// carry third-party (YouTube) headers.
  static bool isSymphonyHost(String host, {String? override}) {
    final h = host.toLowerCase();
    if (h.contains('jettimothycerezo.dev') ||
        h.contains('localhost') ||
        h.contains('192.168.') ||
        h.contains('127.0.0.1')) {
      return true;
    }
    final forced = _normalize(override ?? overrideOrigin);
    if (forced == null) return false;
    final forcedHost = Uri.tryParse(forced)?.host.toLowerCase();
    return forcedHost != null && forcedHost.isNotEmpty && h == forcedHost;
  }

  static String? _normalize(String? origin) {
    if (origin == null) return null;
    var o = origin.trim();
    while (o.endsWith('/')) {
      o = o.substring(0, o.length - 1);
    }
    return o.isEmpty ? null : o;
  }

  static String? _pageOrigin() {
    try {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && !origin.startsWith('null')) return origin;
    } catch (_) {}
    return null;
  }
}
