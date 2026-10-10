import 'package:flutter/material.dart';
import '../../../../../core/theme/symphony_theme.dart';
import '../../../../settings/presentation/controllers/personalization_provider.dart';
import '../../../../settings/presentation/widgets/personalization_dialog.dart';
import '../../widgets/import_playlist_dialog.dart';

/// Pill button showing the user's display name; opens personalization.
class PersonalizeButton extends StatelessWidget {
  final PersonalizationState personalization;
  final SymphonyAccent accent;

  const PersonalizeButton({super.key, required this.personalization, required this.accent});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog(context: context, builder: (_) => const PersonalizationDialog()),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF404040)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline_rounded, size: 16, color: accent.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                personalization.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White "Import Playlist" pill that opens the import dialog.
class ImportPlaylistButton extends StatelessWidget {
  const ImportPlaylistButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        showDialog(context: context, builder: (_) => const ImportPlaylistDialog());
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
      ),
      icon: const Icon(Icons.add, size: 16, color: Colors.black),
      label: const Text(
        'Import Playlist',
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }
}
