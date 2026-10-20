import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:share_plus/share_plus.dart';

import '../../../core/config/links.dart';
import '../../../core/utils/widget_image.dart';
import '../domain/recap.dart';
import 'recap_share_card.dart';

/// Hands a finished card to the system's share sheet. Swapped out in tests.
typedef ShareImage = Future<void> Function(Uint8List png, {required String fileName, required String text});

Future<void> shareWithSystem(Uint8List png, {required String fileName, required String text}) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
    fileNameOverrides: [fileName],
    text: text,
    // Web without file sharing: download the image instead.
    downloadFallbackEnabled: true,
  ));
}

/// Draws [kind] of [recap] as a 1080×1920 picture and shares it with a
/// link to Symphony.
Future<void> shareRecapCard(
  Recap recap,
  RecapCardKind kind, {
  required ui.FlutterView view,
  ShareImage share = shareWithSystem,
}) async {
  final urls = RecapShareCard.artworkFor(recap, kind);
  final loaded = await Future.wait(urls.map(loadNetworkImage));
  final images = <String, ui.Image>{
    for (var i = 0; i < urls.length; i++)
      if (loaded[i] != null) urls[i]: loaded[i]!,
  };
  try {
    final png = await renderWidgetToPng(
      RecapShareCard(recap: recap, kind: kind, images: images),
      size: RecapShareCard.size,
      view: view,
    );
    final slug = recap.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    developer.log('Sharing a ${kind.name} card (${png.length} bytes)', name: 'ForYou');
    await share(
      png,
      fileName: 'symphony-$slug-${kind.name}.png',
      text: 'My ${recap.title} in music, on Symphony. Get it free: ${SymphonyLinks.site}',
    );
  } finally {
    for (final image in images.values) {
      image.dispose();
    }
  }
}
