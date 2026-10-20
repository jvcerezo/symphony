import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio_player/data/services/symphony_audio_handler.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../settings/presentation/controllers/personalization_provider.dart';
import '../data/handler_jam_players.dart';
import '../data/jam_guest_service.dart';
import '../data/jam_discovery.dart';
import '../data/jam_host_service.dart';
import '../data/jam_transport.dart';
import '../domain/jam_state.dart';

/// This device's part in a Jam.
sealed class JamSession {
  const JamSession();
}

/// Not in a Jam. [endReason] says why the last one ended (null when none
/// did or the user left), [error] why starting or joining failed.
class JamIdle extends JamSession {
  const JamIdle({this.endReason, this.error});
  final String? endReason;
  final String? error;
}

/// Starting to host, or connecting to a host. [online] when through the
/// relay rather than this network.
class JamConnecting extends JamSession {
  const JamConnecting({required this.hosting, this.online = false});
  final bool hosting;
  final bool online;
}

class JamHosting extends JamSession {
  const JamHosting({
    required this.code,
    required this.members,
    this.permissions = const JamPermissions(),
    this.discoverable = true,
    this.online = false,
  });

  /// What guests type to join.
  final String code;

  /// Hosted through the relay, so guests can join from anywhere.
  final bool online;
  final List<JamMember> members;
  final JamPermissions permissions;

  /// False when guests can't find this Jam by its code (the discovery port
  /// was taken), so the panel can say so.
  final bool discoverable;

  JamHosting copyWith({List<JamMember>? members, JamPermissions? permissions}) => JamHosting(
        code: code,
        members: members ?? this.members,
        permissions: permissions ?? this.permissions,
        discoverable: discoverable,
        online: online,
      );
}

class JamJoined extends JamSession {
  const JamJoined({required this.hostName, required this.members, required this.permissions});
  final String hostName;
  final List<JamMember> members;
  final JamPermissions permissions;

  JamJoined copyWith({List<JamMember>? members, JamPermissions? permissions}) => JamJoined(
        hostName: hostName,
        members: members ?? this.members,
        permissions: permissions ?? this.permissions,
      );
}

/// Starts, joins and leaves Jams, on the local network or online through
/// the relay (see [jamRelayUrl]).
class JamController extends StateNotifier<JamSession> {
  JamController({
    required SymphonyAudioHandler handler,
    required String Function() displayName,
    Future<JamServer> Function()? bind,
    Future<JamConnection> Function(String host, int port)? connect,
    Future<JamBeacon?> Function({required String code, required int port, required String hostName})? beacon,
    Future<FoundJam?> Function(String code)? find,
    Future<JamServer> Function(String code, void Function() onLost)? hostOnline,
    Future<JamConnection> Function(String code)? joinOnline,
    Future<bool> Function(String code)? onlineExists,
    String Function()? newOnlineCode,
  })  : _handler = handler,
        _displayName = displayName,
        _bind = bind ?? bindLanJamServer,
        _connect = connect ?? connectLanJam,
        _beacon = beacon ?? startJamBeacon,
        _find = find ?? findLanJam,
        _hostOnline = hostOnline ?? ((code, onLost) => hostOnlineJam(code, onLost: onLost)),
        _joinOnline = joinOnline ?? joinOnlineJam,
        _onlineExists = onlineExists ?? onlineJamExists,
        _newOnlineCode = newOnlineCode ?? newOnlineJamCode,
        super(const JamIdle());

  final SymphonyAudioHandler _handler;
  final String Function() _displayName;
  final Future<JamServer> Function() _bind;
  final Future<JamConnection> Function(String host, int port) _connect;
  final Future<JamBeacon?> Function({required String code, required int port, required String hostName}) _beacon;
  final Future<FoundJam?> Function(String code) _find;
  final Future<JamServer> Function(String code, void Function() onLost) _hostOnline;
  final Future<JamConnection> Function(String code) _joinOnline;
  final Future<bool> Function(String code) _onlineExists;
  final String Function() _newOnlineCode;

  JamHostService? _host;
  JamBeacon? _hostBeacon;
  JamGuestService? _guest;
  final _subs = <StreamSubscription<Object?>>[];

  bool get isSupported => lanJamSupported;

  /// Starts hosting: on this network, or [online] through the relay so
  /// guests can join from anywhere.
  Future<void> host({bool online = false}) async {
    if (state is! JamIdle) return;
    state = JamConnecting(hosting: true, online: online);
    try {
      String? code;
      final JamServer server;
      if (online) {
        code = await _freeOnlineCode();
        server = await _hostOnline(code, _lostRelay);
      } else {
        server = await _bind();
      }
      final host = JamHostService(
        player: HandlerJamHostPlayer(_handler),
        server: server,
        hostName: _displayName(),
        code: code,
      );
      _host = host;
      host.start();
      _subs.add(host.membersStream.listen((members) {
        final s = state;
        if (s is JamHosting) state = s.copyWith(members: members);
      }));
      if (online) {
        state = JamHosting(code: host.code, members: host.members, online: true);
        return;
      }
      _hostBeacon = await _beacon(code: host.code, port: host.port, hostName: host.hostName);
      state = JamHosting(code: host.code, members: host.members, discoverable: _hostBeacon != null);
    } catch (e) {
      developer.log('Could not start a Jam: $e', name: 'Jam');
      await _reset();
      state = JamIdle(
        error: online
            ? "Could not start an online Jam. Check that you're connected to the internet."
            : 'Could not start a Jam on this network',
      );
    }
  }

  /// A code no running online Jam uses (a clash is about one in 900 million,
  /// but a stale host would refuse us).
  Future<String> _freeOnlineCode() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final code = _newOnlineCode();
      if (!await _onlineExists(code)) return code;
    }
    throw StateError('No free online Jam code');
  }

  void _lostRelay() {
    if (state is JamHosting) unawaited(_ended('relay_lost'));
  }

  /// Joins the Jam with [code]: a 6-character code online through the
  /// relay, a 4-digit one by finding it on this network.
  Future<void> join({required String code}) async {
    if (state is! JamIdle) return;
    final trimmed = code.trim().toUpperCase();
    if (isOnlineJamCode(trimmed)) return _joinOnlineJam(trimmed);
    state = const JamConnecting(hosting: false);
    final FoundJam? found;
    try {
      found = await _find(trimmed);
    } catch (e) {
      developer.log('Jam discovery failed: $e', name: 'Jam');
      state = const JamIdle(error: 'Could not search this network for Jams.');
      return;
    }
    if (found == null) {
      state = JamIdle(error: "No Jam with code $trimmed on this Wi-Fi. Check the code, and that you're on the same network as the host.");
      return;
    }
    await _joinWith(trimmed, () => _connect(found!.host, found.port),
        unreachable: "Found the Jam but could not connect. The host's firewall may be blocking it.");
  }

  Future<void> _joinOnlineJam(String code) async {
    state = const JamConnecting(hosting: false, online: true);
    final bool exists;
    try {
      exists = await _onlineExists(code);
    } catch (e) {
      developer.log('Could not reach the Jam relay: $e', name: 'Jam');
      state = const JamIdle(error: "Could not reach the online Jam service. Check that you're connected to the internet.");
      return;
    }
    if (!exists) {
      state = JamIdle(error: 'No online Jam with code $code. Check the code with the host.');
      return;
    }
    await _joinWith(code, () => _joinOnline(code), unreachable: 'Could not connect to the online Jam. Try again.');
  }

  /// Joins over the connection [open] makes, then follows the host.
  Future<void> _joinWith(String code, Future<JamConnection> Function() open, {required String unreachable}) async {
    final guest = JamGuestService(player: HandlerJamGuestPlayer(_handler), name: _displayName(), code: code);
    _guest = guest;
    try {
      final connection = await open();
      _subs.add(guest.membersStream.listen((members) {
        final s = state;
        if (s is JamJoined) state = s.copyWith(members: members);
      }));
      _subs.add(guest.permissionsStream.listen((permissions) {
        final s = state;
        if (s is JamJoined) state = s.copyWith(permissions: permissions);
      }));
      _subs.add(guest.statusStream.listen((status) {
        if (status == JamGuestStatus.ended && identical(_guest, guest)) unawaited(_ended(guest.endReason));
      }));
      await guest.join(connection);
      if (guest.status != JamGuestStatus.joined) return;
      state = JamJoined(hostName: guest.hostName, members: guest.members, permissions: guest.permissions);
    } on JamJoinException catch (e) {
      await _reset();
      state = JamIdle(error: e.message);
    } catch (e) {
      developer.log('Could not join the Jam: $e', name: 'Jam');
      await _reset();
      state = JamIdle(error: unreachable);
    }
  }

  /// Host only: whether guests may play, pause, skip and edit the queue
  /// (they can always add songs).
  void setGuestsControlPlayback(bool allowed) {
    final host = _host;
    final s = state;
    if (host == null || s is! JamHosting) return;
    final permissions = JamPermissions(guestsControlPlayback: allowed);
    host.permissions = permissions;
    state = s.copyWith(permissions: permissions);
  }

  /// Ends the Jam when hosting, leaves it when a guest.
  Future<void> leave() async {
    final guest = _guest;
    _guest = null;
    await guest?.leave();
    await _reset();
    state = const JamIdle();
  }

  Future<void> _ended(String? reason) async {
    _guest = null;
    await _reset();
    state = JamIdle(endReason: reason == 'left' ? null : reason);
  }

  Future<void> _reset() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final beacon = _hostBeacon;
    _hostBeacon = null;
    await beacon?.close();
    final host = _host;
    _host = null;
    await host?.stop();
    final guest = _guest;
    _guest = null;
    if (guest != null && guest.status != JamGuestStatus.ended) await guest.leave();
  }

  @override
  void dispose() {
    unawaited(_reset());
    super.dispose();
  }
}

final jamProvider = StateNotifierProvider<JamController, JamSession>((ref) {
  return JamController(
    handler: ref.watch(audioHandlerProvider),
    displayName: () => ref.read(personalizationProvider).displayName,
  );
});
