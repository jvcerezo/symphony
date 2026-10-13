import 'dart:io';

/// Opens a connection to YouTube, where every stream comes from. A DNS
/// lookup alone isn't enough: answers can come from a cache while offline.
Future<bool> canReachInternet() async {
  try {
    final socket = await Socket.connect('www.youtube.com', 443, timeout: const Duration(seconds: 3))
        .timeout(const Duration(seconds: 4));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
