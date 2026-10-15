import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/jam/domain/clock_sync.dart';
import 'package:symphony/features/jam/domain/drift_policy.dart';
import 'package:symphony/features/jam/domain/jam_message.dart';
import 'package:symphony/features/jam/domain/jam_state.dart';

const _song = JamTrack(
  entry: 3,
  sourceId: 'itunes_123',
  title: 'Song',
  artist: 'Artist',
  album: 'Album',
  durationMs: 200000,
  artworkUrl: 'https://art.example/a.jpg',
  videoId: 'dQw4w9WgXcQ',
);

const _state = JamState(rev: 7, queue: [_song], index: 0, playing: true, positionMs: 1500, atHostMs: 1000);

JamMessage _roundTrip(JamMessage m) => JamMessage.decode(m.encode());

void main() {
  group('messages survive encoding', () {
    test('hello, ping, pong, bye', () {
      final hello = _roundTrip(const JamHello(code: '0420', name: 'Jet')) as JamHello;
      expect((hello.v, hello.code, hello.name), (jamProtocolVersion, '0420', 'Jet'));

      expect((_roundTrip(const JamPing(5)) as JamPing).t0, 5);
      final pong = _roundTrip(const JamPong(t0: 5, hostT: 99)) as JamPong;
      expect((pong.t0, pong.hostT), (5, 99));
      expect((_roundTrip(const JamBye('host_ended')) as JamBye).reason, 'host_ended');
    });

    test('welcome with state, members and permissions', () {
      final welcome = _roundTrip(const JamWelcome(
        guestId: 'g1',
        hostName: 'Host',
        state: _state,
        members: [JamMember(id: 'host', name: 'Host', isHost: true), JamMember(id: 'g1', name: 'Guest')],
        permissions: JamPermissions(guestsControlPlayback: false),
      )) as JamWelcome;

      expect(welcome.guestId, 'g1');
      expect(welcome.hostName, 'Host');
      expect(welcome.members, const [JamMember(id: 'host', name: 'Host', isHost: true), JamMember(id: 'g1', name: 'Guest')]);
      expect(welcome.permissions.guestsControlPlayback, isFalse);
      final s = welcome.state;
      expect((s.rev, s.index, s.playing, s.positionMs, s.atHostMs), (7, 0, true, 1500, 1000));
      final t = s.queue.single;
      expect((t.entry, t.sourceId, t.title, t.artist, t.album, t.durationMs, t.artworkUrl, t.videoId),
          (3, 'itunes_123', 'Song', 'Artist', 'Album', 200000, 'https://art.example/a.jpg', 'dQw4w9WgXcQ'));
    });

    test('every request kind', () {
      for (final kind in JamRequestKind.values) {
        final r = _roundTrip(JamRequest(kind, track: _song, index: 2, to: 4, positionMs: 30000)) as JamRequest;
        expect(r.kind, kind);
        expect((r.index, r.to, r.positionMs, r.track?.sourceId), (2, 4, 30000, 'itunes_123'));
      }
    });

    test('reject reasons and member lists', () {
      for (final reason in JamRejectReason.values) {
        expect((_roundTrip(JamReject(reason)) as JamReject).reason, reason);
      }
      final members = _roundTrip(const JamMembersUpdate([JamMember(id: 'g2', name: 'B')])) as JamMembersUpdate;
      expect(members.members.single.name, 'B');
    });
  });

  group('bad frames are refused', () {
    for (final raw in [
      'not json',
      '[]',
      '{"type":"dance"}',
      '{"type":"ping"}',
      '{"type":"pong","t0":"soon","hostT":1}',
      '{"type":"request","kind":"explode"}',
      '{"type":"reject","reason":"bored"}',
    ]) {
      test(raw, () => expect(() => JamMessage.decode(raw), throwsFormatException));
    }
  });

  group('JamTrack', () {
    test('a known video becomes a yt_ track, so the guest skips song matching', () {
      final track = _song.toTrack();
      expect(track.id, 'yt_dQw4w9WgXcQ');
      expect(track.expectedDuration, const Duration(seconds: 200));
      expect(track.artworkUri, Uri.parse('https://art.example/a.jpg'));
    });

    test('without a video it keeps the host id', () {
      const t = JamTrack(sourceId: 'itunes_123', title: 'S', artist: 'A');
      expect(t.toTrack().id, 'itunes_123');
    });

    test('drops what a guest cannot use: local artwork and ids that are not videos', () {
      final t = JamTrack.fromTrack(
        Track(id: 'x', title: 'S', artist: 'A', artworkUri: Uri.file('/covers/a.jpg')),
        videoId: 'itunes_123',
      );
      expect(t.artworkUrl, isNull);
      expect(t.videoId, isNull);
    });
  });

  test('state position runs on while playing and holds while paused', () {
    expect(_state.positionAt(3000), const Duration(milliseconds: 3500));
    const paused = JamState(rev: 1, queue: [], index: -1, playing: false, positionMs: 1500, atHostMs: 1000);
    expect(paused.positionAt(9000), const Duration(milliseconds: 1500));
  });

  group('ClockSync', () {
    test('uses the sample with the shortest round trip', () {
      final sync = ClockSync()
        // Host is 5000 ms ahead; slow sample is skewed by an uneven path.
        ..addSample(t0: 0, hostT: 5300, t1: 400)
        ..addSample(t0: 1000, hostT: 6020, t1: 1040)
        ..addSample(t0: 2000, hostT: 7100, t1: 2200);

      expect(sync.rttMs, 40);
      expect(sync.offsetMs, 5000);
      expect(sync.hostNow(10000), 15000);
    });

    test('forgets old samples so a drifting clock is followed', () {
      final sync = ClockSync(window: 2)
        ..addSample(t0: 0, hostT: 1010, t1: 20) // offset 1000, fastest
        ..addSample(t0: 100, hostT: 2140, t1: 180)
        ..addSample(t0: 200, hostT: 2240, t1: 280);
      expect(sync.offsetMs, 2000);
    });

    test('ignores a sample where time ran backwards', () {
      final sync = ClockSync()..addSample(t0: 100, hostT: 0, t1: 50);
      expect(sync.isReady, isFalse);
      expect(sync.offsetMs, 0);
    });
  });

  group('DriftPolicy', () {
    const policy = DriftPolicy();
    final now = DateTime(2026, 10, 15, 12);
    const s = Duration(seconds: 1);

    test('leaves small drift alone', () {
      expect(policy.correction(actual: s * 60, expected: s * 60 + const Duration(milliseconds: 250), now: now), isNull);
    });

    test('seeks to where the host is, plus the lead', () {
      expect(
        policy.correction(actual: s * 60, expected: s * 61, now: now, lead: const Duration(milliseconds: 100)),
        const Duration(milliseconds: 61100),
      );
    });

    test('waits out the cool-down after a seek', () {
      final justSeeked = now.subtract(s * 2);
      expect(policy.correction(actual: s * 60, expected: s * 62, now: now, lastSeekAt: justSeeked), isNull);
      final longAgo = now.subtract(s * 4);
      expect(policy.correction(actual: s * 60, expected: s * 62, now: now, lastSeekAt: longAgo), s * 62);
    });
  });
}
