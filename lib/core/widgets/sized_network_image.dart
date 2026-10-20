import 'package:flutter/widgets.dart';

/// [Image.network] decoded at the size it is shown, not the size it was
/// downloaded at. Covers come as large as 1000 pixels square: decoded
/// whole, every 48-pixel thumbnail would hold about 4 MB of memory and
/// push other covers out of the image cache, to be decoded again on the
/// next scroll.
///
/// The size is [width] or [height] when given, else the space it is laid
/// out in. Covers are square, so the decoded width is the longer side.
class SizedNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  const SizedNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  /// Decoded widths are rounded up to this, so a cover shown at nearby
  /// sizes shares one decode.
  static const _step = 64;

  /// The width to decode at, in pixels, for a box of [width] by [height]
  /// logical pixels; null when the box is unbounded (decode whole).
  static int? decodeWidth(double width, double height, double pixelRatio) {
    final side = (width.isFinite ? width : 0.0) > (height.isFinite ? height : 0.0) ? width : height;
    if (!side.isFinite || side <= 0) return null;
    final px = (side * pixelRatio).ceil();
    return ((px + _step - 1) ~/ _step) * _step;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    Widget image(int? decode) => Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          cacheWidth: decode,
          errorBuilder: errorBuilder,
        );
    if (width != null && height != null) return image(decodeWidth(width!, height!, ratio));
    return LayoutBuilder(
      builder: (context, constraints) => image(decodeWidth(
        width ?? constraints.maxWidth,
        height ?? constraints.maxHeight,
        ratio,
      )),
    );
  }
}
