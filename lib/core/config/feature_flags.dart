/// Compile-time feature switches, set with `--dart-define`.
abstract final class FeatureFlags {
  /// The in-browser player needs a reachable `server.dart` backend, so it is
  /// off for the static landing-page build. Enable with
  /// `--dart-define=SYMPHONY_WEB_DEMO=true`.
  static const bool webDemoEnabled = bool.fromEnvironment('SYMPHONY_WEB_DEMO');
}
