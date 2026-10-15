import 'dart:convert';

import 'jam_state.dart';

/// Version of the Jam protocol; a guest on another version is turned away.
const jamProtocolVersion = 1;

/// A message between a Jam host and a guest, sent as one JSON text frame.
sealed class JamMessage {
  const JamMessage();

  String get type;
  Map<String, Object?> get fields;

  String encode() => jsonEncode({'type': type, ...fields});

  /// Parses one frame. Throws [FormatException] for anything that isn't a
  /// well-formed message of a known type.
  static JamMessage decode(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map) throw const FormatException('Jam message is not an object');
    final m = json.cast<String, Object?>();
    try {
      return switch (m['type']) {
        'hello' => JamHello(v: m['v'] as int, code: m['code'] as String? ?? '', name: m['name'] as String? ?? ''),
        'welcome' => JamWelcome(
            guestId: m['guestId'] as String,
            hostName: m['hostName'] as String? ?? '',
            state: JamState.fromJson(_map(m['state'])),
            members: _members(m['members']),
            permissions: JamPermissions.fromJson(_map(m['permissions'])),
          ),
        'reject' => JamReject(_reason(m['reason'], JamRejectReason.values)),
        'ping' => JamPing(m['t0'] as int),
        'pong' => JamPong(t0: m['t0'] as int, hostT: m['hostT'] as int),
        'state' => JamStateUpdate(JamState.fromJson(_map(m['state']))),
        'request' => JamRequest(
            _reason(m['kind'], JamRequestKind.values),
            track: m['track'] == null ? null : JamTrack.fromJson(_map(m['track'])),
            index: m['index'] as int?,
            to: m['to'] as int?,
            positionMs: m['positionMs'] as int?,
          ),
        'members' => JamMembersUpdate(_members(m['members'])),
        'permissions' => JamPermissionsUpdate(JamPermissions.fromJson(_map(m['permissions']))),
        'bye' => JamBye(m['reason'] as String? ?? ''),
        _ => throw FormatException('Unknown Jam message type: ${m['type']}'),
      };
    } on FormatException {
      rethrow;
    } catch (e) {
      // Missing or mistyped fields.
      throw FormatException('Malformed Jam message: $e');
    }
  }

  static Map<String, Object?> _map(Object? value) => (value as Map).cast<String, Object?>();

  static List<JamMember> _members(Object? value) =>
      [for (final m in value as List) JamMember.fromJson((m as Map).cast<String, Object?>())];

  static T _reason<T extends Enum>(Object? name, List<T> values) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    throw FormatException('Unknown value: $name');
  }
}

/// Guest → host, first message: asks to join with the room [code].
class JamHello extends JamMessage {
  final int v;
  final String code;
  final String name;
  const JamHello({this.v = jamProtocolVersion, required this.code, required this.name});
  @override
  String get type => 'hello';
  @override
  Map<String, Object?> get fields => {'v': v, 'code': code, 'name': name};
}

/// Host → guest: joined.
class JamWelcome extends JamMessage {
  final String guestId;
  final String hostName;
  final JamState state;
  final List<JamMember> members;
  final JamPermissions permissions;
  const JamWelcome({
    required this.guestId,
    required this.hostName,
    required this.state,
    required this.members,
    required this.permissions,
  });
  @override
  String get type => 'welcome';
  @override
  Map<String, Object?> get fields => {
        'guestId': guestId,
        'hostName': hostName,
        'state': state.toJson(),
        'members': [for (final m in members) m.toJson()],
        'permissions': permissions.toJson(),
      };
}

enum JamRejectReason { badCode, full, version }

/// Host → guest: not joined; the host closes the connection after it.
class JamReject extends JamMessage {
  final JamRejectReason reason;
  const JamReject(this.reason);
  @override
  String get type => 'reject';
  @override
  Map<String, Object?> get fields => {'reason': reason.name};
}

/// Guest → host: clock sync probe, [t0] in guest time (ms).
class JamPing extends JamMessage {
  final int t0;
  const JamPing(this.t0);
  @override
  String get type => 'ping';
  @override
  Map<String, Object?> get fields => {'t0': t0};
}

/// Host → guest: answer to [JamPing], with the host's clock at reply time.
class JamPong extends JamMessage {
  final int t0;
  final int hostT;
  const JamPong({required this.t0, required this.hostT});
  @override
  String get type => 'pong';
  @override
  Map<String, Object?> get fields => {'t0': t0, 'hostT': hostT};
}

/// Host → guests: what is playing now.
class JamStateUpdate extends JamMessage {
  final JamState state;
  const JamStateUpdate(this.state);
  @override
  String get type => 'state';
  @override
  Map<String, Object?> get fields => {'state': state.toJson()};
}

enum JamRequestKind { add, playNext, remove, move, play, pause, seek, next, previous, jump }

/// Guest → host: something the guest did, for the host to apply.
///
/// [index] is the queue position for `remove`, `jump` and the source of
/// `move` (moved [to]); [track] goes with `add` and `playNext`.
class JamRequest extends JamMessage {
  final JamRequestKind kind;
  final JamTrack? track;
  final int? index;
  final int? to;
  final int? positionMs;
  const JamRequest(this.kind, {this.track, this.index, this.to, this.positionMs});
  @override
  String get type => 'request';
  @override
  Map<String, Object?> get fields => {
        'kind': kind.name,
        if (track != null) 'track': track!.toJson(),
        if (index != null) 'index': index,
        if (to != null) 'to': to,
        if (positionMs != null) 'positionMs': positionMs,
      };
}

/// Host → guests: who is in the Jam, host first.
class JamMembersUpdate extends JamMessage {
  final List<JamMember> members;
  const JamMembersUpdate(this.members);
  @override
  String get type => 'members';
  @override
  Map<String, Object?> get fields => {'members': [for (final m in members) m.toJson()]};
}

/// Host → guests: what guests may do changed.
class JamPermissionsUpdate extends JamMessage {
  final JamPermissions permissions;
  const JamPermissionsUpdate(this.permissions);
  @override
  String get type => 'permissions';
  @override
  Map<String, Object?> get fields => {'permissions': permissions.toJson()};
}

/// Either side: leaving. From the host it ends the Jam.
class JamBye extends JamMessage {
  final String reason;
  const JamBye([this.reason = '']);
  @override
  String get type => 'bye';
  @override
  Map<String, Object?> get fields => {'reason': reason};
}
