import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/android_video_output_size.dart';

void main() {
  group('androidSuperResolutionOutputSize', () {
    test('upscales a 720p stream to fit a 1080p landscape screen', () {
      final result = androidSuperResolutionOutputSize(
        sourceWidth: 1280,
        sourceHeight: 720,
        screenPhysicalWidth: 2400,
        screenPhysicalHeight: 1080,
      );

      expect(result, const AndroidVideoOutputSize(1920, 1080));
    });

    test('keeps the source size when the portrait view is smaller', () {
      final result = androidSuperResolutionOutputSize(
        sourceWidth: 1280,
        sourceHeight: 720,
        screenPhysicalWidth: 1080,
        screenPhysicalHeight: 2400,
      );

      expect(result, const AndroidVideoOutputSize(1280, 720));
    });

    test('keeps a 1080p stream on a 1080p-tall screen', () {
      final result = androidSuperResolutionOutputSize(
        sourceWidth: 1920,
        sourceHeight: 1080,
        screenPhysicalWidth: 2400,
        screenPhysicalHeight: 1080,
      );

      expect(result, const AndroidVideoOutputSize(1920, 1080));
    });

    test('caps the upscale at 2x', () {
      final result = androidSuperResolutionOutputSize(
        sourceWidth: 854,
        sourceHeight: 480,
        screenPhysicalWidth: 2400,
        screenPhysicalHeight: 1080,
      );

      expect(result, const AndroidVideoOutputSize(1708, 960));
    });

    test('fills a 1440p screen from 1080p without passing 2x', () {
      final result = androidSuperResolutionOutputSize(
        sourceWidth: 1920,
        sourceHeight: 1080,
        screenPhysicalWidth: 2560,
        screenPhysicalHeight: 1440,
      );

      expect(result, const AndroidVideoOutputSize(2560, 1440));
    });

    test('returns the source size for unusable dimensions', () {
      final result = androidSuperResolutionOutputSize(
        sourceWidth: 1280,
        sourceHeight: 720,
        screenPhysicalWidth: 0,
        screenPhysicalHeight: 1080,
      );

      expect(result, const AndroidVideoOutputSize(1280, 720));
    });
  });
}
