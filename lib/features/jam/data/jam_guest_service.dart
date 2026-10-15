import 'dart:async';
import 'dart:developer' as developer;

import '../../audio_player/domain/entities/track.dart';
import '../../audio_player/domain/playback_remote.dart';
import '../domain/clock_sync.dart';
import '../domain/drift_policy.dart';
import '../domain/jam_message.dart';
import '../domain/jam_state.dart';
import 'jam_players.dart';
import 'jam_transport.dart';

enum JamGuestStatus { connecting, syncing, joined, ended }

/// Joining failed: the host turned the guest away ([reason]) or didn't
/// answer.
class JamJoinException implements Exception {
  const JamJoinException(this.message, {this.reason});
  final String message;
  final JamRejectReason? reason;
  @override
  String toString() => 'JamJoinException: $message';
}

/// Follows a Jam host on a guest device.
///
/// While joined, the guest's player plays what the host plays, at the
/// host's position: it estimates the host's clock with pings, loads each
/// song where the host is now (not from the start), and seeks back into
/// place when it drifts. The user's own actions on the player become
/// requests to the host (this service is the player's [PlaybackRemote]).
class JamGuestService implements PlaybackRemote {
  JamGuestService({
    required JamGuestPlayer player,
    required this.name,
    required this.code,
    int Function()? clock,
    this.policy = const DriftPolicy(),
    this.driftInterval = const Duration(seconds: 2),
    this.resyncInterval = const Duration(seconds: 30),
    this.silenceLimit = const Duration(seconds: 15),
    this.joinTimeout = const Duration(seconds: 5),
    this.pings = 6,
  })  : _player = player,
        _clock = clock ?? _wallClock;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final JamGuestPlayer _player;
  final int Function() _clock;
  final String name;
  final String code;
  final DriftPolicy policy;
  final Duration driftInterval;
  final Duration resyncInterval;

  /// No state from the host for this long means it is gone.
  final Duration silenceLimit;
  final Duration joinTimeout;

  /// Clock sync probes sent on joining.
  final int pings;

  final ClockSync clockSync = ClockSync();

  JamConnection? _connection;
  Completer<JamMessage>? _answer;
  final _pongs = <int, Completer<void>>{};

  final _statusController = StreamController<JamGuestStatus>.broadcast();
  final _membersController = StreamController<List<JamMember>>.broadcast();

  JamGuestStatus _status = JamGuestStatus.connecting;
  String? _endReason;
  String? _guestId;
  String _hostName = '';
  List<JamMember> _members = const [];
  JamPermissions _permissions = const JamPermissions();

  JamState _state = JamState.empty;
  int _lastHeard = 0;
  String _queueKey = '';
  int? _loadedEntry;
  DateTime? _lastSeekAt;
  bool _measureSeek = false;

  /// Added to seek targets to make up for the time a seek takes to be
  /// heard; learned from how far off the guest lands after seeking.
  Duration _seekLead = Duration.zero;

  Timer? _driftTimer;
  Timer? _resyncTimer;

  JamGuestStatus get status => _status;
  Stream<JamGuestStatus> get statusStream => _statusController.stream;

  /// Why the Jam ended for this guest: `left`, `host_ended`, `host_left`,
  /// `host_silent`.
  String? get endReason => _endReason;
  String? get guestId => _guestId;
  String get hostName => _hostName;
  List<JamMember> get members => _members;
  Stream<List<JamMember>> get membersStream => _membersController.stream;
  JamPermissions get permissions => _permissions;
  JamState get state => _state;

  /// Joins over [connection]. Throws [JamJoinException] when the host turns
  /// the guest away or doesn't answer within [joinTimeout].
  Future<void> join(JamConnection connection) async {
    _connection = connection;
    _setStatus(JamGuestStatus.connecting);
    _answer = Completer<JamMessage>();
    connection.messages.listen(_onMessage, onDone: _onClosed);
    connection.send(JamHello(code: code, name: name).encode());

    final JamMessage answer;
    try {
      answer = await _answer!.future.timeout(joinTimeout);
    } on TimeoutException {
      await _end('no_answer');
      throw const JamJoinException('The host did not answer');
    } on JamJoinException {
      await _end('no_answer');
      rethrow;
    }
    if (answer is JamReject) {
      await _end('rejected');
      throw JamJoinException(_rejectMessage(answer.reason), reason: answer.reason);
    }
    final welcome = answer as JamWelcome;
    _guestId = welcome.guestId;
    _hostName = welcome.hostName;
    _permissions = welcome.permissions;
    _setMembers(welcome.members);
    if (welcome.state.rev > _state.rev) _state = welcome.state;
    _lastHeard = _clock();

    _setStatus(JamGuestStatus.syncing);
    await _syncClock(pings);
    if (_status == JamGuestStatus.ended) return;

    _player.remote = this;
    _setStatus(JamGuestStatus.joined);
    _applyState(_state, previous: JamState.empty);
    _driftTimer = Timer.periodic(driftInterval, (_) => _tick());
    _resyncTimer = Timer.periodic(resyncInterval, (_) => unawaited(_syncClock(3)));
  }

  static String _rejectMessage(JamRejectReason reason) => switch (reason) {
        JamRejectReason.badCode => 'Wrong Jam code',
        JamRejectReason.full => 'This Jam is full',
        JamRejectReason.version => 'Update Symphony to join this Jam',
      };

  /// Leaves the Jam. Playback carries on here, no longer following.
  Future<void> leave() async {
    _connection?.send(const JamBye('left').encode());
    await _end('left');
  }

  // Messages.

  void _onMessage(String raw) {
    final JamMessage message;
    try {
      message = JamMessage.decode(raw);
    } on FormatException catch (e) {
      developer.log('Ignoring bad Jam message: $e', name: 'Jam');
      return;
    }
    switch (message) {
      case JamWelcome() || JamReject():
        final answer = _answer;
        if (answer != null && !answer.isCompleted) answer.complete(message);
      case JamPong(:final t0, :final hostT):
        clockSync.addSample(t0: t0, hostT: hostT, t1: _clock());
        _pongs.remove(t0)?.complete();
      case JamStateUpdate(:final state):
        _lastHeard = _clock();
        if (state.rev <= _state.rev) return;
        final previous = _state;
        _state = state;
        if (_status == JamGuestStatus.joined) _applyState(state, previous: previous);
      case JamMembersUpdate(:final members):
        _setMembers(members);
      case JamBye():
        unawaited(_end('host_ended'));
      default:
        break;
    }
  }

  void _onClosed() {
    final answer = _answer;
    if (answer != null && !answer.isCompleted) {
      answer.completeError(const JamJoinException('The host closed the connection'));
    }
    unawaited(_end('host_left'));
  }

  Future<void> _syncClock(int count) async {
    for (var i = 0; i < count; i++) {
      if (_status == JamGuestStatus.ended) return;
      var t0 = _clock();
      while (_pongs.containsKey(t0)) {
        t0++;
      }
      final pong = Completer<void>();
      _pongs[t0] = pong;
      _connection?.send(JamPing(t0).encode());
      try {
        await pong.future.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        _pongs.remove(t0);
      }
    }
  }

  // Following the host.

  int _hostNow() => clockSync.hostNow(_clock());

  void _applyState(JamState s, {required JamState previous}) {
    final queueKey = '${s.index}|${s.queue.map((t) => '${t.entry}:${t.videoId ?? ''}').join(',')}';
    if (queueKey != _queueKey) {
      _queueKey = queueKey;
      _player.followQueue([for (final t in s.queue) t.toTrack()], s.index);
    }

    final current = s.current;
    if (current == null) {
      _loadedEntry = null;
      if (_player.isPlaying) unawaited(_player.setPlaying(false));
      return;
    }

    final hostNow = _hostNow();
    final expected = s.positionAt(hostNow);
    if (current.entry != _loadedEntry) {
      _loadedEntry = current.entry;
      _lastSeekAt = null;
      _measureSeek = false;
      final entry = current.entry;
      _player.loadCurrent(startAt: expected, play: s.playing).then((_) {
        // Loading took a while; catch up with the host straight away.
        if (_loadedEntry == entry) _checkDrift(ignoreCooldown: true);
      }, onError: (Object e) {
        developer.log('Jam guest could not load "${current.title}": $e', name: 'Jam');
      });
      return;
    }

    if (_player.isLoading) return;
    if (s.playing != _player.isPlaying) unawaited(_player.setPlaying(s.playing));

    if (!s.playing) {
      if ((_player.position - expected).abs() > policy.threshold) unawaited(_player.seek(expected));
      return;
    }
    // The host seeked: follow at once, cool-down or not.
    final jumped = previous.current?.entry == current.entry &&
        (previous.positionAt(hostNow) - expected).abs() > policy.threshold;
    _checkDrift(ignoreCooldown: jumped);
  }

  void _tick() {
    if (_status != JamGuestStatus.joined) return;
    if (_clock() - _lastHeard > silenceLimit.inMilliseconds) {
      developer.log('Nothing from the Jam host for ${silenceLimit.inSeconds}s', name: 'Jam');
      unawaited(_end('host_silent'));
      return;
    }
    _checkDrift();
  }

  void _checkDrift({bool ignoreCooldown = false}) {
    final s = _state;
    if (_status != JamGuestStatus.joined ||
        s.current?.entry != _loadedEntry ||
        _player.isLoading ||
        !s.playing ||
        !_player.isPlaying) {
      return;
    }
    final expected = s.positionAt(_hostNow());
    final actual = _player.position;
    final now = DateTime.fromMillisecondsSinceEpoch(_clock());

    // Learn how late seeks land from where the last one ended up.
    if (_measureSeek && _lastSeekAt != null && now.difference(_lastSeekAt!) >= policy.cooldown) {
      _measureSeek = false;
      final error = actual - expected;
      if (error.abs() < const Duration(seconds: 1)) {
        final lead = _seekLead - error ~/ 2;
        _seekLead = lead.isNegative
            ? Duration.zero
            : (lead > _maxSeekLead ? _maxSeekLead : lead);
      }
    }

    final target = policy.correction(
      actual: actual,
      expected: expected,
      now: now,
      lastSeekAt: ignoreCooldown ? null : _lastSeekAt,
      lead: _seekLead,
    );
    if (target == null) return;
    developer.log('Jam drift ${(actual - expected).inMilliseconds}ms; seeking to $target', name: 'Jam');
    _lastSeekAt = now;
    _measureSeek = true;
    unawaited(_player.seek(target));
  }

  static const _maxSeekLead = Duration(milliseconds: 400);

  /// The lead currently added to seeks (exposed for tests and diagnostics).
  Duration get seekLead => _seekLead;

  // The user's actions, sent to the host.

  void _request(JamRequest request) {
    if (_status != JamGuestStatus.joined) return;
    _connection?.send(request.encode());
  }

  static JamTrack _jamTrack(Track track) =>
      JamTrack.fromTrack(track, videoId: track.id.startsWith('yt_') ? track.id.substring(3) : null);

  @override
  void play() => _request(const JamRequest(JamRequestKind.play));
  @override
  void pause() => _request(const JamRequest(JamRequestKind.pause));
  @override
  void seek(Duration position) => _request(JamRequest(JamRequestKind.seek, positionMs: position.inMilliseconds));
  @override
  void next() => _request(const JamRequest(JamRequestKind.next));
  @override
  void previous() => _request(const JamRequest(JamRequestKind.previous));
  @override
  void jumpTo(int index) => _request(JamRequest(JamRequestKind.jump, index: index));
  @override
  void add(Track track) => _request(JamRequest(JamRequestKind.add, track: _jamTrack(track)));
  @override
  void playNext(Track track) => _request(JamRequest(JamRequestKind.playNext, track: _jamTrack(track)));
  @override
  void remove(int index) => _request(JamRequest(JamRequestKind.remove, index: index));
  @override
  void move(int from, int to) => _request(JamRequest(JamRequestKind.move, index: from, to: to));

  // Lifecycle.

  void _setStatus(JamGuestStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void _setMembers(List<JamMember> members) {
    _members = List.unmodifiable(members);
    if (!_membersController.isClosed) _membersController.add(_members);
  }

  Future<void> _end(String reason) async {
    if (_status == JamGuestStatus.ended) return;
    _endReason = reason;
    _driftTimer?.cancel();
    _resyncTimer?.cancel();
    for (final p in _pongs.values) {
      if (!p.isCompleted) p.complete();
    }
    _pongs.clear();
    _player.remote = null;
    _setStatus(JamGuestStatus.ended);
    developer.log('Left the Jam ($reason)', name: 'Jam');
    await _connection?.close();
    await _statusController.close();
    await _membersController.close();
  }
}
