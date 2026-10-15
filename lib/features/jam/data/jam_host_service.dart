import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import '../../audio_player/domain/entities/track.dart';
import '../domain/jam_message.dart';
import '../domain/jam_state.dart';
import 'jam_players.dart';
import 'jam_transport.dart';

/// Runs a Jam on the hosting device.
///
/// The host's player is the real one. Guests send requests, which are
/// applied here, and every guest gets the resulting [JamState]: when
/// something changes, when the position jumps (a seek), and as a heartbeat.
class JamHostService {
  JamHostService({
    required JamHostPlayer player,
    required JamServer server,
    required this.hostName,
    String? code,
    JamPermissions permissions = const JamPermissions(),
    int Function()? clock,
    Random? random,
    this.tick = const Duration(milliseconds: 500),
    this.heartbeat = const Duration(seconds: 5),
    this.helloTimeout = const Duration(seconds: 5),
  })  : _player = player,
        _server = server,
        _clock = clock ?? _wallClock,
        _permissions = permissions,
        code = code ?? _newCode(random ?? Random.secure());

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  static String _newCode(Random random) => random.nextInt(10000).toString().padLeft(4, '0');

  final JamHostPlayer _player;
  final JamServer _server;
  final int Function() _clock;

  final String hostName;

  /// The room code guests must give to join.
  final String code;

  JamPermissions _permissions;

  /// What guests may do. Changing it tells every guest.
  JamPermissions get permissions => _permissions;
  set permissions(JamPermissions value) {
    _permissions = value;
    if (!_stopped) _sendAll(JamPermissionsUpdate(value).encode());
  }

  /// How often the host checks whether guests need a new state.
  final Duration tick;

  /// Longest gap between two states, so guests notice a host that is gone.
  final Duration heartbeat;

  /// How long a new connection has to say hello.
  final Duration helloTimeout;

  int get port => _server.port;

  final _guests = <String, _Guest>{};
  int _nextGuest = 1;

  final _entries = Expando<int>('jam entry');
  int _nextEntry = 1;
  final _videoIds = Expando<String>('jam video id');
  final _lookedUp = Expando<bool>('jam video lookup');

  final _members = StreamController<List<JamMember>>.broadcast();
  StreamSubscription<JamConnection>? _connectionsSub;
  StreamSubscription<void>? _changesSub;
  Timer? _ticker;

  int _rev = 0;
  JamState _sent = JamState.empty;
  String _sentKey = '';
  int _sentAt = 0;
  bool _started = false;
  bool _stopped = false;

  /// Everyone in the Jam, host first.
  List<JamMember> get members => [
        JamMember(id: 'host', name: hostName, isHost: true),
        for (final e in _guests.entries) JamMember(id: e.key, name: e.value.name),
      ];

  Stream<List<JamMember>> get membersStream => _members.stream;

  /// The state guests were last sent.
  JamState get lastState => _sent;

  void start() {
    if (_started) return;
    _started = true;
    _connectionsSub = _server.connections.listen(_onConnection);
    _changesSub = _player.changes.listen((_) => _broadcastIfChanged());
    _ticker = Timer.periodic(tick, (_) => _broadcastIfChanged());
    _broadcastIfChanged(force: true);
  }

  /// Ends the Jam for everyone.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _ticker?.cancel();
    await _changesSub?.cancel();
    await _connectionsSub?.cancel();
    final guests = _guests.values.toList();
    _guests.clear();
    for (final g in guests) {
      g.connection.send(const JamBye('host_ended').encode());
      await g.connection.close();
    }
    await _server.close();
    await _members.close();
  }

  // Connections.

  void _onConnection(JamConnection connection) {
    String? guestId;
    final helloTimer = Timer(helloTimeout, () {
      if (guestId == null) connection.close();
    });

    connection.messages.listen(
      (raw) {
        final JamMessage message;
        try {
          message = JamMessage.decode(raw);
        } on FormatException catch (e) {
          developer.log('Ignoring bad Jam message: $e', name: 'Jam');
          return;
        }
        final id = guestId;
        if (id != null) {
          _onGuestMessage(id, message);
          return;
        }
        helloTimer.cancel();
        if (message is! JamHello) {
          connection.close();
          return;
        }
        final reason = _rejectReason(message);
        if (reason != null) {
          connection.send(JamReject(reason).encode());
          connection.close();
          return;
        }
        guestId = _admit(connection, message);
      },
      onDone: () {
        helloTimer.cancel();
        final id = guestId;
        if (id != null) _removeGuest(id);
      },
    );
  }

  JamRejectReason? _rejectReason(JamHello hello) {
    if (_stopped) return JamRejectReason.full;
    if (hello.v != jamProtocolVersion) return JamRejectReason.version;
    if (hello.code != code) return JamRejectReason.badCode;
    if (_guests.length >= jamMaxGuests) return JamRejectReason.full;
    return null;
  }

  String _admit(JamConnection connection, JamHello hello) {
    final id = 'g${_nextGuest++}';
    _guests[id] = _Guest(connection, _cleanName(hello.name));
    _broadcastIfChanged();
    connection.send(JamWelcome(
      guestId: id,
      hostName: hostName,
      state: _sent,
      members: members,
      permissions: permissions,
    ).encode());
    _announceMembers();
    developer.log('Guest $id joined the Jam', name: 'Jam');
    return id;
  }

  static String _cleanName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Guest';
    return trimmed.length > 32 ? trimmed.substring(0, 32) : trimmed;
  }

  void _removeGuest(String id) {
    if (_guests.remove(id) == null) return;
    developer.log('Guest $id left the Jam', name: 'Jam');
    _announceMembers();
  }

  void _announceMembers() {
    final list = members;
    if (!_members.isClosed) _members.add(list);
    _sendAll(JamMembersUpdate(list).encode());
  }

  void _onGuestMessage(String id, JamMessage message) {
    final guest = _guests[id];
    if (guest == null) return;
    switch (message) {
      case JamPing(:final t0):
        guest.connection.send(JamPong(t0: t0, hostT: _clock()).encode());
      case JamRequest():
        _apply(message);
      case JamBye():
        guest.connection.close();
      default:
        break;
    }
  }

  // Requests.

  static const _controlKinds = {
    JamRequestKind.play,
    JamRequestKind.pause,
    JamRequestKind.seek,
    JamRequestKind.next,
    JamRequestKind.previous,
    JamRequestKind.jump,
    JamRequestKind.remove,
    JamRequestKind.move,
  };

  void _apply(JamRequest r) {
    if (_controlKinds.contains(r.kind) && !permissions.guestsControlPlayback) return;
    final track = r.track?.toTrack();
    final index = r.index;
    final Future<void>? pending = switch (r.kind) {
      JamRequestKind.add when track != null => _sync(() => _player.add(track)),
      JamRequestKind.playNext when track != null => _sync(() => _player.playNext(track)),
      JamRequestKind.remove when index != null => _sync(() => _player.remove(index)),
      JamRequestKind.move when index != null && r.to != null => _sync(() => _player.move(index, r.to!)),
      JamRequestKind.play => _player.play(),
      JamRequestKind.pause => _player.pause(),
      JamRequestKind.seek when r.positionMs != null => _player.seek(Duration(milliseconds: max(0, r.positionMs!))),
      JamRequestKind.next => _player.next(),
      JamRequestKind.previous => _player.previous(),
      JamRequestKind.jump when index != null => _player.jumpTo(index),
      _ => null,
    };
    if (pending == null) return;
    pending.then((_) => _broadcastIfChanged(), onError: (Object e) {
      developer.log('Jam request ${r.kind.name} failed: $e', name: 'Jam');
      _broadcastIfChanged();
    });
    _broadcastIfChanged();
  }

  static Future<void> _sync(void Function() edit) {
    edit();
    return Future.value();
  }

  // State.

  int _entryOf(Track track) => _entries[track] ??= _nextEntry++;

  String? _videoIdOf(Track track, {required bool isCurrent}) {
    final known = isCurrent ? _player.currentVideoId : null;
    if (isYouTubeVideoId(known)) return known;
    final cached = _videoIds[track];
    if (cached != null) return cached;
    if (_lookedUp[track] == null) {
      _lookedUp[track] = true;
      _player.videoIdFor(track).then((id) {
        if (!isYouTubeVideoId(id)) return;
        _videoIds[track] = id!;
        _broadcastIfChanged();
      }, onError: (Object _) {});
    }
    return null;
  }

  JamState _snapshot(int now) {
    final queue = _player.queue;
    final index = _player.index;
    return JamState(
      rev: _rev,
      queue: [
        for (var i = 0; i < queue.length; i++)
          JamTrack.fromTrack(
            queue[i],
            entry: _entryOf(queue[i]),
            videoId: _videoIdOf(queue[i], isCurrent: i == index),
          ),
      ],
      index: index,
      playing: _player.isPlaying,
      positionMs: _player.position.inMilliseconds,
      atHostMs: now,
    );
  }

  static String _keyOf(JamState s) =>
      '${s.index}|${s.playing}|${s.queue.map((t) => '${t.entry}:${t.videoId ?? ''}').join(',')}';

  /// How far the real position may stray from where the last state said it
  /// would be before guests are told (a seek, or the host stalling).
  static const _positionSlack = Duration(milliseconds: 500);

  void _broadcastIfChanged({bool force = false}) {
    if (_stopped) return;
    final now = _clock();
    final next = _snapshot(now);
    final key = _keyOf(next);
    final drift = (next.positionAt(now) - _sent.positionAt(now)).abs();
    final due = now - _sentAt >= heartbeat.inMilliseconds;
    if (!force && key == _sentKey && drift <= _positionSlack && !due) return;

    _rev++;
    _sent = JamState(
      rev: _rev,
      queue: next.queue,
      index: next.index,
      playing: next.playing,
      positionMs: next.positionMs,
      atHostMs: next.atHostMs,
    );
    _sentKey = key;
    _sentAt = now;
    _sendAll(JamStateUpdate(_sent).encode());
  }

  void _sendAll(String message) {
    for (final g in _guests.values) {
      g.connection.send(message);
    }
  }
}

class _Guest {
  _Guest(this.connection, this.name);
  final JamConnection connection;
  final String name;
}
