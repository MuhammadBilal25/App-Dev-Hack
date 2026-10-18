import 'package:flutter_test/flutter_test.dart';
import 'package:huddle/features/scenario2/deep_link.dart';
import 'package:huddle/features/scenario2/guest_api.dart';

void main() {
  group('nascon:// deep links (spec 6.3)', () {
    test('entity and stream links map to the Day 2 screens', () {
      expect(deepLinkTarget(Uri.parse('nascon://entity/match-m1')), '/live/match/match-m1');
      expect(deepLinkTarget(Uri.parse('nascon://stream/cs-session-101')), '/live/costream/cs-session-101');
      expect(deepLinkTarget(Uri.parse('nascon://entity/player-alpha-1')), '/player/player-alpha-1');
      expect(deepLinkTarget(Uri.parse('nascon://entity/club-alpha-1')), '/club/club-alpha-1');
      expect(deepLinkTarget(Uri.parse('nascon://entity/unknown-1')), isNull);
    });

    test('links whose host was dropped still map', () {
      expect(deepLinkTarget(Uri.parse('/match-m1')), '/live/match/match-m1');
      expect(deepLinkTarget(Uri.parse('/stream/cs-session-101')), '/live/costream/cs-session-101');
      expect(deepLinkTarget(Uri.parse('/home')), isNull);
    });
  });

  test('guest web routes (QR redirects) map to app screens', () {
    expect(webRouteTarget('/web/matches/match-m1/live'), '/live/match/match-m1');
    expect(webRouteTarget('/web/matches/match-m1/notice?state=postponed'), '/live/match/match-m1');
    expect(webRouteTarget('/web/costream/cs-session-101'), '/live/costream/cs-session-101');
    expect(webRouteTarget('/web/players/player-alpha-1'), '/player/player-alpha-1');
    expect(webRouteTarget('/web/clubs/club-alpha-1'), '/club/club-alpha-1');
    expect(webRouteTarget('/elsewhere'), isNull);
  });

  test('media URLs on localhost point at the API host the phone uses', () {
    expect(mediaUrl('http://localhost:8888/live/k/index.m3u8', 'http://192.168.1.20:8080'), 'http://192.168.1.20:8888/live/k/index.m3u8');
    expect(mediaUrl('rtmp://localhost:1935/live/k', 'http://10.0.2.2:8080'), 'rtmp://10.0.2.2:1935/live/k');
    expect(mediaUrl('https://cdn.example/x.m3u8', 'http://10.0.2.2:8080'), 'https://cdn.example/x.m3u8');
  });
}
