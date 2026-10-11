import 'dart:async';

import 'package:http/http.dart' as http;

/// Reports bytes received so far and the total once the server reveals it.
typedef ChunkProgressCallback = void Function(int received, int? total);

/// Downloads [url] as consecutive HTTP Range requests.
///
/// YouTube throttles a single full-file GET to roughly playback speed, while
/// ranged chunks arrive at line speed (a 3.7 MB song: ~60 s vs ~1.2 s). If a
/// server ignores `Range` and answers 200, the whole body is streamed once.
Stream<List<int>> chunkedDownload(
  http.Client client,
  Uri url, {
  Map<String, String>? headers,
  int chunkSize = 1 << 20,
  Duration chunkTimeout = const Duration(seconds: 20),
  ChunkProgressCallback? onProgress,
}) async* {
  var offset = 0;
  int? total;

  while (total == null || offset < total) {
    final request = http.Request('GET', url)
      ..headers.addAll(headers ?? const {})
      ..headers['Range'] = 'bytes=$offset-${offset + chunkSize - 1}';
    final response = await client.send(request).timeout(chunkTimeout);

    if (response.statusCode == 200) {
      // Range ignored: this response is the whole file.
      final whole = response.contentLength;
      await for (final chunk in response.stream.timeout(chunkTimeout)) {
        offset += chunk.length;
        onProgress?.call(offset, whole);
        yield chunk;
      }
      return;
    }
    if (response.statusCode == 416 && total == null && offset == 0) {
      await response.stream.drain<void>().catchError((_) {});
      return; // Empty resource.
    }
    if (response.statusCode != 206) {
      await response.stream.drain<void>().catchError((_) {});
      throw http.ClientException('HTTP ${response.statusCode} at byte $offset', url);
    }

    total ??= _totalFromContentRange(response.headers['content-range']);

    var received = 0;
    await for (final chunk in response.stream.timeout(chunkTimeout)) {
      received += chunk.length;
      offset += chunk.length;
      onProgress?.call(offset, total);
      yield chunk;
    }
    if (received == 0) {
      throw http.ClientException('Empty range response at byte $offset', url);
    }
    // Unknown total: a short chunk means we reached the end.
    if (total == null && received < chunkSize) return;
  }
}

int? _totalFromContentRange(String? value) {
  // e.g. "bytes 0-1048575/3733947"
  if (value == null) return null;
  final slash = value.lastIndexOf('/');
  if (slash < 0) return null;
  return int.tryParse(value.substring(slash + 1).trim());
}
