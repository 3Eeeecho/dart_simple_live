import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class AndroidVideoOutputSize {
  final int width;
  final int height;

  const AndroidVideoOutputSize(this.width, this.height);

  @override
  bool operator ==(Object other) {
    return other is AndroidVideoOutputSize &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// Texture size for the Android FSR shader.
///
/// media_kit otherwise sizes the Surface to the source. The shader only runs
/// when the output is larger than the source, so a 720p stream on a 1080p
/// screen would never be upscaled. This keeps the source size when the current
/// screen cannot show a larger picture.
AndroidVideoOutputSize androidSuperResolutionOutputSize({
  required int sourceWidth,
  required int sourceHeight,
  required double screenPhysicalWidth,
  required double screenPhysicalHeight,
  double maxScale = 2,
}) {
  if (sourceWidth < 2 ||
      sourceHeight < 2 ||
      !screenPhysicalWidth.isFinite ||
      !screenPhysicalHeight.isFinite ||
      screenPhysicalWidth < 2 ||
      screenPhysicalHeight < 2 ||
      maxScale <= 1) {
    return AndroidVideoOutputSize(
      math.max(sourceWidth, 0),
      math.max(sourceHeight, 0),
    );
  }

  final fit = math.min(
    screenPhysicalWidth / sourceWidth,
    screenPhysicalHeight / sourceHeight,
  );
  // A tiny upscale costs a full shader pass and is hard to see.
  if (fit < 1.05) {
    return AndroidVideoOutputSize(sourceWidth, sourceHeight);
  }

  final factor = math.min(maxScale, fit);
  final width = _evenDimension(sourceWidth * factor);
  final height = _evenDimension(sourceHeight * factor);
  if (width <= sourceWidth || height <= sourceHeight) {
    return AndroidVideoOutputSize(sourceWidth, sourceHeight);
  }
  return AndroidVideoOutputSize(width, height);
}

int _evenDimension(double value) {
  final rounded = value.floor();
  if (rounded <= 2) {
    return 2;
  }
  return rounded.isEven ? rounded : rounded - 1;
}

(int, int)? androidSuperResolutionOutputForCurrentScreen(
  int sourceWidth,
  int sourceHeight,
) {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) {
    return null;
  }
  final screen = views.first.physicalSize;
  final target = androidSuperResolutionOutputSize(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    screenPhysicalWidth: screen.width,
    screenPhysicalHeight: screen.height,
  );
  return (target.width, target.height);
}
