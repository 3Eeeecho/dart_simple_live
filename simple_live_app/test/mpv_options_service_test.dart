import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/mpv_options_service.dart';

void main() {
  test('keeps direct d3d11va selection unchanged', () {
    expect(
      MpvOptionsService.parseOptions('--hwdec=d3d11va'),
      {'hwdec': 'd3d11va'},
    );
  });

  test('accepts an mpv-style decoder option line', () {
    expect(
      MpvOptionsService.parseOptions('--hwdec d3d11va'),
      {'hwdec': 'd3d11va'},
    );
  });

  test('caps lookback at 15 minutes and sizes the back buffer', () {
    expect(MpvOptionsService.clampLookbackMinutes(-1), 0);
    expect(MpvOptionsService.clampLookbackMinutes(15), 15);
    expect(MpvOptionsService.clampLookbackMinutes(16), 15);
    expect(MpvOptionsService.lookbackBackBytesLabel(0), '8MiB');
    expect(MpvOptionsService.lookbackBackBytesLabel(15), '1200MiB');
    expect(MpvOptionsService.lookbackMaxBytesLabel(15), '1232MiB');
    expect(
      MpvOptionsService.lookbackBackBytesLabel(15, mebibytesPerMinute: 32),
      '480MiB',
    );
    expect(
      MpvOptionsService.lookbackMaxBytesLabel(15, mebibytesPerMinute: 32),
      '512MiB',
    );
  });

  test('android super resolution copies frames so the shader can run', () {
    expect(
      MpvOptionsService.androidSuperResolutionHwdec(hardwareDecode: true),
      'mediacodec-copy',
    );
    expect(
      MpvOptionsService.androidSuperResolutionHwdec(hardwareDecode: false),
      'no',
    );
  });

  test('uses copy decode unless NVIDIA super resolution is on', () {
    expect(
      MpvOptionsService.windowsHwdec(nvidiaSuperResolution: false),
      'd3d11va-copy',
    );
    expect(
      MpvOptionsService.windowsHwdec(nvidiaSuperResolution: true),
      'd3d11va',
    );
  });

  test('uses the later option value for the same key', () {
    expect(
      MpvOptionsService.parseOptions(
        '--hwdec=auto-safe\n--hwdec=d3d11va',
      ),
      {'hwdec': 'd3d11va'},
    );
  });
}
