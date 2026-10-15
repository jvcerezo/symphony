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

/// Starting to host, or connecting to a host.
class JamConnecting extends JamSession {
  const JamConnecting({required this.hosting});
  final bool hosting;
}

class JamHosting extends JamSession {
  const JamHosting({
    required this.code,
    required this.members,
    this.permissions = const JamPermissions(),
    this.discoverable = true,
  });

  /// What guests type to join.
  final String code;
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

/// Starts, joins and leaves Jams on the local network.
class JamController extends StateNotifier<JamSession> {
  JamController({
    required SymphonyAudioHandler handler,
    required String Function() displayName,
    Future<JamServer> Function()? bind,
    Future<JamConnection> Function(String host, int port)? connect,
    Future<JamBeacon?> Function({required String code, required int port, required String hostName})? beacon,
    Future<FoundJam?> Function(String code)? find,
  })  : _handler = handler,
        _displayName = displayName,
        _bind = bind ?? bindLanJamServer,
        _connect = connect ?? connectLanJam,
        _beacon = beacon ?? startJamBeacon,
        _find = find ?? findLanJam,
        super(const JamIdle());

  final SymphonyAudioHandler _handler;
  final String Function() _displayName;
  final Future<JamServer> Function() _bind;
  final Future<JamConnection> Function(String host, int port) _connect;
  final Future<JamBeacon?> Function({required String code, required int port, required String hostName}) _beacon;
  final Future<FoundJam?> Function(String code) _find;

  JamHostService? _host;
  JamBeacon? _hostBeacon;
  JamGuestService? _guest;
  final _subs = <StreamSubscription<Object?>>[];

  bool get isSupported => lanJamSupported;

  Future<void> host() async {
    if (state is! JamIdle) return;
    state = const JamConnecting(hosting: true);
    try {
      final server = await _bind();
      final host = JamHostService(
        player: HandlerJamHostPlayer(_handler),
        server: server,
        hostName: _displayName(),
      );
      _host = host;
      host.start();
      _subs.add(host.membersStream.listen((members) {
        final s = state;
        if (s is JamHosting) state = s.copyWith(members: members);
      }));
      _hostBeacon = await _beacon(code: host.code, port: host.port, hostName: host.hostName);
      state = JamHosting(code: host.code, members: host.members, discoverable: _hostBeacon != null);
    } catch (e) {
      developer.log('Could not start a Jam: $e', name: 'Jam');
      await _reset();
      state = const JamIdle(error: 'Could not start a Jam on this network');
    }
  }

  /// Finds the Jam with [code] on this network and joins it.
  Future<void> join({required String code}) async {
    if (state is! JamIdle) return;
    final trimmed = code.trim();
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
    final guest = JamGuestService(player: HandlerJamGuestPlayer(_handler), name: _displayName(), code: trimmed);
    _guest = guest;
    try {
      final connection = await _connect(found.host, found.port);
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
      state = const JamIdle(error: "Found the Jam but could not connect. The host's firewall may be blocking it.");
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
