/// The cached range a live lookback slider can seek inside.
class LookbackSpan {
  final Duration start;
  final Duration end;
  final Duration position;

  const LookbackSpan({
    required this.start,
    required this.end,
    required this.position,
  });

  Duration get length => end - start;

  bool get canScrub => length >= const Duration(milliseconds: 800);

  Duration get behind {
    final value = end - position;
    return value.isNegative ? Duration.zero : value;
  }

  double get fraction {
    if (!canScrub) {
      return 1;
    }
    final raw = (position - start).inMilliseconds / length.inMilliseconds;
    if (raw.isNaN) {
      return 1;
    }
    return raw.clamp(0.0, 1.0);
  }

  Duration positionForFraction(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    return start +
        Duration(milliseconds: (length.inMilliseconds * clamped).round());
  }
}

LookbackSpan? lookbackSpanFromSeconds({
  required double? startSeconds,
  required double? endSeconds,
  required Duration position,
}) {
  if (startSeconds == null ||
      endSeconds == null ||
      !startSeconds.isFinite ||
      !endSeconds.isFinite ||
      endSeconds <= startSeconds) {
    return null;
  }
  final start = _durationFromSeconds(startSeconds);
  final end = _durationFromSeconds(endSeconds);
  return LookbackSpan(
    start: start,
    end: end,
    position: _clampDuration(position, start, end),
  );
}

/// Used when mpv does not report a seekable range yet.
/// [edge] is the newest playback time seen, [cap] is the configured limit.
LookbackSpan lookbackSpanFromPlayback({
  required Duration position,
  required Duration edge,
  required Duration cap,
}) {
  final end = edge > position ? edge : position;
  var start = Duration.zero;
  if (cap > Duration.zero && end > cap) {
    start = end - cap;
  }
  return LookbackSpan(
    start: start,
    end: end,
    position: _clampDuration(position, start, end),
  );
}

String lookbackBehindLabel(Duration behind) {
  if (behind < const Duration(seconds: 2)) {
    return "直播";
  }
  final total = behind.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final secondText = seconds.toString().padLeft(2, "0");
  if (hours > 0) {
    final minuteText = minutes.toString().padLeft(2, "0");
    return "-$hours:$minuteText:$secondText";
  }
  return "-$minutes:$secondText";
}

Duration _durationFromSeconds(double seconds) {
  if (seconds <= 0) {
    return Duration.zero;
  }
  return Duration(milliseconds: (seconds * 1000).round());
}

Duration _clampDuration(Duration value, Duration start, Duration end) {
  if (value < start) {
    return start;
  }
  if (value > end) {
    return end;
  }
  return value;
}
