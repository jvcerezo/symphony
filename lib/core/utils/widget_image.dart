import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Paints [widget] at [size] (logical pixels) off screen and returns it as
/// a PNG [pixelRatio] times larger, e.g. 360×640 at 3 → 1080×1920.
///
/// Nothing is shown. The widget is built once, so anything it shows must
/// be ready: pass decoded images (see [loadNetworkImage]) rather than
/// widgets that load them.
Future<Uint8List> renderWidgetToPng(
  Widget widget, {
  required Size size,
  required ui.FlutterView view,
  double pixelRatio = 3,
}) async {
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.center, child: boundary),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: 1,
    ),
  );
  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();

  final buildOwner = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(textDirection: TextDirection.ltr, child: widget),
    ),
  ).attachToRenderTree(buildOwner);
  try {
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    // Unmount, so the widget's resources (and its State) are released.
    buildOwner
      ..buildScope(root, () {})
      ..finalizeTree();
    root.update(RenderObjectToWidgetAdapter<RenderBox>(container: boundary));
    buildOwner.finalizeTree();
  }
}

/// [url] downloaded and decoded, or null when it can't be within [timeout].
Future<ui.Image?> loadNetworkImage(String? url, {Duration timeout = const Duration(seconds: 6)}) async {
  if (url == null || url.isEmpty) return null;
  final done = Completer<ui.Image?>();
  final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (_, __) {
      if (!done.isCompleted) done.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future.timeout(timeout, onTimeout: () {
    stream.removeListener(listener);
    return null;
  });
}
