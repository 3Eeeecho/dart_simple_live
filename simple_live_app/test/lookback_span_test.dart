import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/lookback_span.dart';

void main() {
  test('reads a seekable cache range and clamps the playhead', () {
    final span = lookbackSpanFromSeconds(
      startSeconds: 10,
      endSeconds: 70,
      position: const Duration(seconds: 80),
    );

    expect(span, isNotNull);
    expect(span!.start, const Duration(seconds: 10));
    expect(span.end, const Duration(seconds: 70));
    expect(span.position, const Duration(seconds: 70));
    expect(span.behind, Duration.zero);
    expect(span.fraction, 1);
    expect(span.positionForFraction(0), const Duration(seconds: 10));
  });

  test('rejects an empty cache range', () {
    expect(
      lookbackSpanFromSeconds(
        startSeconds: 5,
        endSeconds: 5,
        position: Duration.zero,
      ),
      isNull,
    );
  });

  test('playback fallback keeps the configured cap', () {
    final span = lookbackSpanFromPlayback(
      position: const Duration(minutes: 20),
      edge: const Duration(minutes: 20),
      cap: const Duration(minutes: 15),
    );

    expect(span.start, const Duration(minutes: 5));
    expect(span.end, const Duration(minutes: 20));
    expect(span.canScrub, isTrue);
  });

  test('behind label stays readable', () {
    expect(lookbackBehindLabel(const Duration(milliseconds: 800)), "直播");
    expect(lookbackBehindLabel(const Duration(seconds: 65)), "-1:05");
    expect(lookbackBehindLabel(const Duration(hours: 1, seconds: 2)), "-1:00:02");
  });
}
