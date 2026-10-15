import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/breakpoints.dart';
import '../../../core/theme/symphony_theme.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../audio_player/presentation/controllers/now_playing_panel_provider.dart';
import '../data/jam_transport.dart';
import '../domain/jam_state.dart';
import 'jam_providers.dart';

/// Opens the Jam: the side panel on desktop, a bottom sheet on mobile.
void openJam(BuildContext context, WidgetRef ref) {
  if (Breakpoints.isDesktop(context)) {
    ref.read(nowPlayingPanelProvider.notifier).state = NowPlayingPanel.jam;
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SymphonyTheme.panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                const Text('Jam', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.close_rounded, color: SymphonyTheme.textSecondary),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
          const Expanded(child: JamPanel()),
        ],
      ),
    ),
  );
}

/// Header pill that opens the Jam; lit while this device is in one.
/// Hidden where Jams aren't available (web).
class JamButton extends ConsumerWidget {
  /// An icon only, for tight headers.
  final bool compact;

  const JamButton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!lanJamSupported) return const SizedBox.shrink();
    final session = ref.watch(jamProvider);
    final accent = ref.watch(accentThemeProvider);
    final active = session is JamHosting || session is JamJoined;
    final color = active ? accent.primary : Colors.white;

    if (compact) {
      return IconButton(
        tooltip: active ? 'In a Jam' : 'Jam',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: Icon(Icons.groups_rounded, color: color, size: 24),
        onPressed: () => openJam(context, ref),
      );
    }
    return InkWell(
      onTap: () => openJam(context, ref),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SymphonyTheme.cardHover,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? accent.primary : SymphonyTheme.cardActive),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_rounded, size: 16, color: active ? accent.primary : Colors.white),
            const SizedBox(width: 6),
            Text(
              active ? 'In a Jam' : 'Jam',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Start, join or manage a Jam.
class JamPanel extends ConsumerWidget {
  const JamPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!lanJamSupported) {
      return const _Message(
        icon: Icons.wifi_off_rounded,
        text: 'Jams work in the Symphony app for Windows, Android and Mac.',
      );
    }
    final session = ref.watch(jamProvider);
    return switch (session) {
      JamIdle() => _IdleView(session: session),
      JamConnecting(:final hosting) => _Message(
          icon: Icons.groups_rounded,
          text: hosting ? 'Starting a Jam…' : 'Joining the Jam…',
          busy: true,
        ),
      JamHosting() => _HostingView(session: session),
      JamJoined() => _JoinedView(session: session),
    };
  }
}

const _sectionStyle = TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6);
const _bodyStyle = TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13, height: 1.4);

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool busy;

  const _Message({required this.icon, required this.text, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            else
              Icon(icon, size: 36, color: SymphonyTheme.textMuted),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center, style: _bodyStyle),
          ],
        ),
      ),
    );
  }
}

class _IdleView extends ConsumerStatefulWidget {
  final JamIdle session;

  const _IdleView({required this.session});

  @override
  ConsumerState<_IdleView> createState() => _IdleViewState();
}

class _IdleViewState extends ConsumerState<_IdleView> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  String? _formError;

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  void _join() {
    final address = parseJamAddress(_address.text);
    final code = _code.text.trim();
    if (address == null) {
      setState(() => _formError = 'Enter the address the host sees, like 192.168.1.5:41234');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      setState(() => _formError = 'The Jam code is 4 digits');
      return;
    }
    setState(() => _formError = null);
    ref.read(jamProvider.notifier).join(host: address.host, port: address.port, code: code);
  }

  static String? _endMessage(String? reason) => switch (reason) {
        null => null,
        'host_ended' => 'The host ended the Jam.',
        _ => 'Lost the connection to the host. The music keeps playing here.',
      };

  @override
  Widget build(BuildContext context) {
    final notice = widget.session.error ?? _endMessage(widget.session.endReason);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text(
          'Listen together with people on the same Wi-Fi. Everyone hears the same song at the same time, and guests can add to the queue.',
          style: _bodyStyle,
        ),
        if (notice != null) ...[
          const SizedBox(height: 14),
          _Notice(text: notice),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => ref.read(jamProvider.notifier).host(),
          icon: const Icon(Icons.wifi_tethering_rounded),
          label: const Text('Start a Jam'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(48),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 28),
        const Text('JOIN A JAM', style: _sectionStyle),
        const SizedBox(height: 10),
        _Field(
          controller: _address,
          label: 'Host address',
          hint: '192.168.1.5:41234',
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: 10),
        _Field(
          controller: _code,
          label: 'Jam code',
          hint: '4 digits',
          keyboardType: TextInputType.number,
          maxLength: 4,
          onSubmitted: (_) => _join(),
        ),
        if (_formError != null) ...[
          const SizedBox(height: 8),
          Text(_formError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _join,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: SymphonyTheme.cardActive),
          ),
          child: const Text('Join', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final int? maxLength;
  final ValueChanged<String> onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.keyboardType,
    required this.onSubmitted,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        labelStyle: const TextStyle(color: SymphonyTheme.textSecondary),
        hintStyle: const TextStyle(color: SymphonyTheme.textMuted),
        filled: true,
        fillColor: SymphonyTheme.cardHover,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SymphonyTheme.cardHover, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: SymphonyTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }
}

class _HostingView extends ConsumerWidget {
  final JamHosting session;

  const _HostingView({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(jamProvider.notifier);
    final accent = ref.watch(accentThemeProvider);
    final address = session.addresses.isEmpty ? null : '${session.addresses.first}:${session.port}';
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text('Guests join with this address and code:', style: _bodyStyle),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: SymphonyTheme.cardHover, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CODE', style: _sectionStyle),
              const SizedBox(height: 4),
              SelectableText(
                session.code,
                style: TextStyle(color: accent.primary, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8),
              ),
              const SizedBox(height: 12),
              const Text('ADDRESS', style: _sectionStyle),
              const SizedBox(height: 4),
              if (address == null)
                const Text('Connect to Wi-Fi so guests can find you.', style: TextStyle(color: Colors.white))
              else
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        address,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy address and code',
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.copy_rounded, size: 20, color: SymphonyTheme.textSecondary),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: 'Symphony Jam: $address, code ${session.code}'));
                        ScaffoldMessenger.maybeOf(context)
                            ?.showSnackBar(const SnackBar(content: Text('Copied the Jam address and code')));
                      },
                    ),
                  ],
                ),
              if (session.addresses.length > 1) ...[
                const SizedBox(height: 4),
                Text(
                  'Other networks: ${session.addresses.skip(1).map((a) => '$a:${session.port}').join(', ')}',
                  style: const TextStyle(color: SymphonyTheme.textMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (isWindows) ...[
          const SizedBox(height: 12),
          const _Notice(
            text: 'If Windows asks about the firewall, allow Symphony on private networks, or guests won\'t be able to connect.',
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: session.permissions.guestsControlPlayback,
          onChanged: controller.setGuestsControlPlayback,
          activeThumbColor: accent.primary,
          title: const Text('Guests can control playback', style: TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: const Text('Play, pause, skip and reorder. Adding songs is always on.', style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        _Members(members: session.members),
        const SizedBox(height: 20),
        _LeaveButton(label: 'End Jam', onPressed: controller.leave),
      ],
    );
  }
}

class _JoinedView extends ConsumerWidget {
  final JamJoined session;

  const _JoinedView({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentThemeProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            Icon(Icons.groups_rounded, color: accent.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Jamming with ${session.hostName}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          session.permissions.guestsControlPlayback
              ? 'You hear what ${session.hostName} plays. Your play, skip and queue changes go to everyone.'
              : 'Only ${session.hostName} controls playback. You can still add songs to the queue.',
          style: _bodyStyle,
        ),
        const SizedBox(height: 16),
        _Members(members: session.members),
        const SizedBox(height: 20),
        _LeaveButton(label: 'Leave Jam', onPressed: ref.read(jamProvider.notifier).leave),
      ],
    );
  }
}

class _Members extends StatelessWidget {
  final List<JamMember> members;

  const _Members({required this.members});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('IN THIS JAM (${members.length})', style: _sectionStyle),
        const SizedBox(height: 6),
        if (members.length < 2)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No guests yet.', style: _bodyStyle),
          ),
        for (final m in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: SymphonyTheme.cardActive,
              child: Text(
                m.name.isEmpty ? '?' : m.name.characters.first.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(m.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
            trailing: m.isHost ? const Text('Host', style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 12)) : null,
          ),
      ],
    );
  }
}

class _LeaveButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _LeaveButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.redAccent,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Colors.redAccent),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
