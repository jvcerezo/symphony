import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/audio_player/domain/playback_remote.dart';
import 'package:symphony/features/jam/data/jam_guest_service.dart';
import 'package:symphony/features/jam/data/jam_host_service.dart';
import 'package:symphony/features/jam/data/jam_players.dart';
import 'package:symphony/features/jam/data/jam_transport.dart';
import 'package:symphony/features/jam/domain/jam_message.dart';
import 'package:symphony/features/jam/domain/jam_state.dart';

import 'fake_jam_relay.dart';

Track _song(String id) => Track(id: id, title: 'Song $id', artist: 'Artist', expectedDuration: const Duration(minutes: 3));

/// The host's player: a plain queue that does what it is told.
class _HostPlayer implements JamHostPlayer {
  _HostPlayer(this.queue);

  @override
  List<Track> queue;
  @override
  int index = 0;
  @override
  bool isPlaying = true;
  Duration _position = const Duration(seconds: 10);
  DateTime _positionAt = DateTime.now();
  @override
  String? currentVideoId;
  final videoIds = <String, String>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Duration get position => isPlaying ? _position + DateTime.now().difference(_positionAt) : _position;

  void _set(Duration p) {
    _position = p;
    _positionAt = DateTime.now();
  }

  void _changed() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<String?> videoIdFor(Track track) async => videoIds[track.id];

  @override
  Future<void> play() async {
    _set(position);
    isPlaying = true;
    _changed();
  }

  @override
  Future<void> pause() async {
    _set(position);
    isPlaying = false;
    _changed();
  }

  @override
  Future<void> seek(Duration p) async {
    _set(p);
    _changed();
  }

  @override
  Future<void> next() => jumpTo(index + 1);
  @override
  Future<void> previous() => jumpTo(index - 1);
  @override
  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    _set(Duration.zero);
    _changed();
  }

  @override
  void add(Track track) {
    queue = [...queue, track];
    _changed();
  }

  @override
  void playNext(Track track) {
    queue = [...queue]..insert(index + 1, track);
    _changed();
  }

  @override
  void remove(int i) {
    queue = [...queue]..removeAt(i);
    if (i < index) index--;
    _changed();
  }

  @override
  void move(int from, int to) {
    final q = [...queue];
    q.insert(to, q.removeAt(from));
    queue = q;
    _changed();
  }
}

/// A guest's player that records what the Jam asked of it.
class _GuestPlayer implements JamGuestPlayer {
  PlaybackRemote? currentRemote;
  List<Track> queue = [];
  int index = -1;
  final loads = <({Duration startAt, bool play, String id})>[];
  final seeks = <Duration>[];
  @override
  bool isPlaying = false;
  @override
  bool isLoading = false;
  Duration _position = Duration.zero;
  DateTime _positionAt = DateTime.now();

  @override
  set remote(PlaybackRemote? remote) => currentRemote = remote;

  @override
  Duration get position => isPlaying ? _position + DateTime.now().difference(_positionAt) : _position;

  void _set(Duration p) {
    _position = p;
    _positionAt = DateTime.now();
  }

  @override
  void followQueue(List<Track> tracks, int index) {
    queue = tracks;
    this.index = index;
  }

  @override
  Future<void> loadCurrent({required Duration startAt, required bool play}) async {
    loads.add((startAt: startAt, play: play, id: queue[index].id));
    _set(startAt);
    isPlaying = play;
  }

  @override
  Future<void> setPlaying(bool playing) async {
    _set(position);
    isPlaying = playing;
  }

  @override
  Future<void> seek(Duration p) async {
    seeks.add(p);
    _set(p);
  }
}

Future<void> until(bool Function() done, {String? reason}) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: reason);
}

void main() {
  group('on the local network', () => _suite(online: false));
  group('online through the relay', () => _suite(online: true));
}

/// The same Jam over either transport: a LAN socket, or the relay protocol
/// (against a local stand-in for the Cloudflare relay).
void _suite({required bool online}) {
  const onlineCode = 'ABC234';
  late JamServer server;
  FakeJamRelay? relay;

  Future<JamServer> bind() async {
    if (!online) return bindLanJamServer(loopbackOnly: true);
    relay ??= await FakeJamRelay.start();
    final server = await hostOnlineJam(onlineCode, relay: relay!.url);
    // Guests are turned away until the relay has seen the host.
    for (var i = 0; i < 100 && !relay!.hasHost(onlineCode); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return server;
  }

  Future<JamConnection> connect() =>
      online ? joinOnlineJam(onlineCode, relay: relay!.url) : connectLanJam('127.0.0.1', server.port);
  late _HostPlayer hostPlayer;
  late JamHostService host;
  final guests = <JamGuestService>[];

  setUp(() async {
    server = await bind();
    hostPlayer = _HostPlayer([_song('a'), _song('b')])..videoIds['a'] = 'aaaaaaaaaaa';
    host = JamHostService(player: hostPlayer, server: server, hostName: 'Host', code: '1234')..start();
  });

  tearDown(() async {
    for (final g in guests) {
      if (g.status != JamGuestStatus.ended) await g.leave();
    }
    guests.clear();
    await host.stop();
    await relay?.close();
    relay = null;
  });

  Future<(JamGuestService, _GuestPlayer)> joinGuest(String name, {String code = '1234'}) async {
    final player = _GuestPlayer();
    final guest = JamGuestService(player: player, name: name, code: code, pings: 3);
    guests.add(guest);
    await guest.join(await connect());
    return (guest, player);
  }

  test('a guest joins mid-song and plays the same upload from where the host is', () async {
    final (guest, player) = await joinGuest('Ana');

    expect(guest.status, JamGuestStatus.joined);
    expect(guest.hostName, 'Host');
    expect(player.currentRemote, same(guest));
    await until(() => player.loads.isNotEmpty);
    expect(player.queue.map((t) => t.id), ['yt_aaaaaaaaaaa', 'b']);
    final load = player.loads.single;
    expect(load.id, 'yt_aaaaaaaaaaa');
    expect(load.play, isTrue);
    // The host is 10 s in and has kept playing since.
    expect(load.startAt, greaterThanOrEqualTo(const Duration(seconds: 10)));
    expect(load.startAt, lessThan(const Duration(seconds: 12)));
    expect(host.members.map((m) => m.name), ['Host', 'Ana']);
  });

  test('one guest adds a song and pauses; every guest follows', () async {
    final (ana, anaPlayer) = await joinGuest('Ana');
    final (_, benPlayer) = await joinGuest('Ben');
    await until(() => benPlayer.loads.isNotEmpty);

    ana.add(_song('c'));
    await until(() => benPlayer.queue.length == 3, reason: 'add reaches the other guest');
    expect(hostPlayer.queue.map((t) => t.id), ['a', 'b', 'c']);

    ana.pause();
    await until(() => !benPlayer.isPlaying && !anaPlayer.isPlaying, reason: 'pause reaches everyone');
    expect(hostPlayer.isPlaying, isFalse);

    ana.next();
    await until(() => benPlayer.loads.length == 2, reason: 'skip loads the next song');
    expect(benPlayer.loads.last.id, 'b');
    expect(benPlayer.loads.last.play, isFalse);
  });

  test('a host seek moves guests at once', () async {
    final (_, player) = await joinGuest('Ana');
    await until(() => player.loads.isNotEmpty);

    await hostPlayer.seek(const Duration(seconds: 90));
    await until(() => player.seeks.isNotEmpty);
    expect(player.seeks.last, greaterThanOrEqualTo(const Duration(seconds: 90)));
    expect(player.position - hostPlayer.position, lessThan(const Duration(milliseconds: 300)));
  });

  test('a guest that drifts is seeked back into place', () async {
    final player = _GuestPlayer();
    final guest = JamGuestService(
      player: player,
      name: 'Ana',
      code: '1234',
      pings: 3,
      driftInterval: const Duration(milliseconds: 100),
    );
    guests.add(guest);
    await guest.join(await connect());
    await until(() => player.loads.isNotEmpty);

    // The guest's audio stalls and falls 2 s behind.
    player._set(player.position - const Duration(seconds: 2));
    await until(() => player.seeks.isNotEmpty);
    expect((player.position - hostPlayer.position).abs(), lessThan(const Duration(milliseconds: 300)));
  });

  test('guests may only add songs when the host keeps control', () async {
    host.permissions = const JamPermissions(guestsControlPlayback: false);
    final (ana, _) = await joinGuest('Ana');

    ana.pause();
    ana.add(_song('c'));
    await until(() => hostPlayer.queue.length == 3);
    expect(hostPlayer.isPlaying, isTrue);
  });

  test('guests hear about a change of permissions at once', () async {
    final (ana, _) = await joinGuest('Ana');
    expect(ana.permissions.guestsControlPlayback, isTrue);

    host.permissions = const JamPermissions(guestsControlPlayback: false);
    await until(() => !ana.permissions.guestsControlPlayback);
  });

  test('a wrong code is turned away', () async {
    await expectLater(
      joinGuest('Eve', code: '9999'),
      throwsA(isA<JamJoinException>().having((e) => e.reason, 'reason', JamRejectReason.badCode)),
    );
    expect(host.members, hasLength(1));
  });

  test('the Jam is full at $jamMaxGuests guests', () async {
    for (var i = 0; i < jamMaxGuests; i++) {
      await joinGuest('G$i');
    }
    await expectLater(
      joinGuest('Late'),
      throwsA(isA<JamJoinException>().having((e) => e.reason, 'reason', JamRejectReason.full)),
    );
  });

  test('a guest who leaves goes back to normal playback', () async {
    final (ana, player) = await joinGuest('Ana');
    await ana.leave();

    expect(player.currentRemote, isNull);
    await until(() => host.members.length == 1);
  });

  test('when the host ends the Jam, guests stop following', () async {
    final (ana, player) = await joinGuest('Ana');
    await host.stop();

    await until(() => ana.status == JamGuestStatus.ended);
    expect(ana.endReason, 'host_ended');
    expect(player.currentRemote, isNull);
  });

  test('a silent connection is closed if it never says hello', () async {
    await host.stop();
    server = await bind();
    host = JamHostService(
      player: hostPlayer,
      server: server,
      hostName: 'Host',
      code: '1234',
      helloTimeout: const Duration(milliseconds: 100),
    )..start();

    final lurker = await connect();
    final closed = Completer<void>();
    lurker.messages.listen((_) {}, onDone: closed.complete);
    await closed.future.timeout(const Duration(seconds: 3));
  });
}
