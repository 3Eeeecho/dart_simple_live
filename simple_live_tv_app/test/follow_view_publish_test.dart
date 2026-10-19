import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/models/db/follow_user.dart';
import 'package:simple_live_tv_app/services/follow_user_service.dart';

FollowUser makeUser(
  String id, {
  int liveStatus = 1,
  bool special = false,
  String tag = '全部',
  String name = 'user',
  DateTime? addTime,
  String siteId = 'bilibili',
}) {
  final follow = FollowUser(
    id: id,
    roomId: id,
    siteId: siteId,
    userName: name,
    face: '',
    addTime: addTime ?? DateTime(2026, 1, 1),
    isSpecialFollow: special,
    tag: tag,
  );
  follow.liveStatus.value = liveStatus;
  return follow;
}

void main() {
  group('compareFollowUsersValue', () {
    test('special follow wins over live status', () {
      final special = makeUser('a', liveStatus: 1, special: true);
      final living = makeUser('b', liveStatus: 2);
      final sorted = [living, special]..sort(compareFollowUsersValue);
      expect(sorted.first.id, 'a');
    });

    test('living users come before offline users', () {
      final offline = makeUser('a', liveStatus: 1);
      final living = makeUser('b', liveStatus: 2);
      final sorted = [offline, living]..sort(compareFollowUsersValue);
      expect(sorted.map((e) => e.id).toList(), ['b', 'a']);
    });

    test('same status falls back to newest follow first', () {
      final older = makeUser('a', addTime: DateTime(2026, 1, 1));
      final newer = makeUser('b', addTime: DateTime(2026, 2, 1));
      final sorted = [older, newer]..sort(compareFollowUsersValue);
      expect(sorted.map((e) => e.id).toList(), ['b', 'a']);
    });
  });

  group('distinctFollowUsers', () {
    test('keeps first item per siteId|roomId', () {
      final first = makeUser('same', name: 'first');
      final second = makeUser('same', name: 'second');
      final distinct = distinctFollowUsers([first, second]);
      expect(distinct.length, 1);
      expect(distinct.single.userName, 'first');
    });
  });

  group('buildFollowDisplayList', () {
    final all = [
      makeUser('offline', liveStatus: 1, addTime: DateTime(2026, 3, 1)),
      makeUser('live', liveStatus: 2, addTime: DateTime(2026, 1, 1)),
      makeUser('tagged', liveStatus: 1, tag: '游戏', name: 'GameRoom'),
    ];

    test('puts living rooms first and keeps everything by default', () {
      final display = buildFollowDisplayList(
        all,
        tagName: FollowUserService.allTagName,
        onlyLive: false,
        keyword: '',
      );
      expect(display.length, 3);
      expect(display.first.id, 'live');
    });

    test('filters by tag', () {
      final display = buildFollowDisplayList(
        all,
        tagName: '游戏',
        onlyLive: false,
        keyword: '',
      );
      expect(display.map((e) => e.id).toList(), ['tagged']);
    });

    test('filters by live-only and keyword', () {
      final living = buildFollowDisplayList(
        all,
        tagName: FollowUserService.allTagName,
        onlyLive: true,
        keyword: '',
      );
      expect(living.map((e) => e.id).toList(), ['live']);

      final byName = buildFollowDisplayList(
        all,
        tagName: FollowUserService.allTagName,
        onlyLive: false,
        keyword: 'game',
      );
      expect(byName.map((e) => e.id).toList(), ['tagged']);
    });

    test('returns an empty list when nothing matches', () {
      final display = buildFollowDisplayList(
        all,
        tagName: 'missing-tag',
        onlyLive: false,
        keyword: '',
      );
      expect(display, isEmpty);
    });
  });

  group('shouldPublishNow', () {
    final now = DateTime(2026, 5, 1, 12, 0, 0);
    const interval = Duration(milliseconds: 250);

    test('first publish always allowed', () {
      expect(
        shouldPublishNow(now: now, last: null, interval: interval, force: false),
        isTrue,
      );
    });

    test('throttles inside the interval', () {
      expect(
        shouldPublishNow(
          now: now,
          last: now.subtract(const Duration(milliseconds: 100)),
          interval: interval,
          force: false,
        ),
        isFalse,
      );
    });

    test('allows once the interval passed', () {
      expect(
        shouldPublishNow(
          now: now,
          last: now.subtract(const Duration(milliseconds: 250)),
          interval: interval,
          force: false,
        ),
        isTrue,
      );
    });

    test('force ignores the throttle', () {
      expect(
        shouldPublishNow(
          now: now,
          last: now.subtract(const Duration(milliseconds: 1)),
          interval: interval,
          force: true,
        ),
        isTrue,
      );
    });
  });
}
