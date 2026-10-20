import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/symphony_theme.dart';
import '../data/jam_links.dart';
import 'jam_panel.dart';
import 'jam_providers.dart';

/// A Jam code from an invite link, waiting for the user to say yes.
final pendingJamInviteProvider = StateProvider<String?>((ref) => null);

/// App start (from `main.dart`): invite links that open the app become a
/// pending invite, which [offerJamInvite] puts to the user.
void startJamLinks(ProviderContainer container, {JamLinks? links}) {
  (links ?? JamLinks()).listen((code) => container.read(pendingJamInviteProvider.notifier).state = code);
}

/// Asks whether to join the Jam with [code], and joins (leaving any Jam
/// this device is in) if so. A link never joins by itself.
Future<void> offerJamInvite(BuildContext context, WidgetRef ref, String code) async {
  final inJam = ref.read(jamProvider) is JamHosting || ref.read(jamProvider) is JamJoined;
  final join = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: SymphonyTheme.surfaceElevated,
      title: const Text('Join this Jam?', style: TextStyle(color: Colors.white)),
      content: Text(
        inJam
            ? 'You were invited to the Jam $code. Joining it ends the Jam you’re in now.'
            : 'You were invited to the Jam $code. Everyone in it hears the same songs at the same time.',
        style: const TextStyle(color: SymphonyTheme.textSecondary, height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Join')),
      ],
    ),
  );
  if (join != true || !context.mounted) return;
  final controller = ref.read(jamProvider.notifier);
  if (inJam) await controller.leave();
  if (!context.mounted) return;
  openJam(context, ref);
  await controller.join(code: code);
}
