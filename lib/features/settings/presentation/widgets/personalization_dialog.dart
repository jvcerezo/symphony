import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../../core/widgets/app_update_dialog.dart';
import '../../../../core/widgets/symphony_brand_logo.dart';
import '../../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../controllers/personalization_provider.dart';

class PersonalizationDialog extends ConsumerStatefulWidget {
  const PersonalizationDialog({super.key});

  @override
  ConsumerState<PersonalizationDialog> createState() => _PersonalizationDialogState();
}

class _PersonalizationDialogState extends ConsumerState<PersonalizationDialog> {
  late TextEditingController _nameController;
  late TextEditingController _instanceController;

  @override
  void initState() {
    super.initState();
    final current = ref.read(personalizationProvider);
    _nameController = TextEditingController(text: current.userName);
    _instanceController = TextEditingController(text: current.instanceName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instanceController.dispose();
    super.dispose();
  }

  void _onNameChanged(String val) {
    setState(() {
      if (val.trim().isNotEmpty && (_instanceController.text.isEmpty || _instanceController.text == 'Symphony')) {
        _instanceController.text = "${val.trim()}'s Symphony";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentThemeProvider);
    final enteredName = _nameController.text.trim();
    final initial = enteredName.isNotEmpty ? enteredName[0].toUpperCase() : 'S';

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF333333)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  enteredName.isEmpty
                      ? const SymphonyBrandLogo(size: 48)
                      : Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.primary,
                            boxShadow: [
                              BoxShadow(
                                color: accent.primary.withOpacity(0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Personalize Symphony',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Add your name to customize your experience',
                          style: TextStyle(
                            fontSize: 12,
                            color: SymphonyTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: SymphonyTheme.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Name Field
              const Text(
                'YOUR NAME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: SymphonyTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                onChanged: _onNameChanged,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Jett',
                  hintStyle: const TextStyle(color: SymphonyTheme.textMuted),
                  filled: true,
                  fillColor: const Color(0xFF282828),
                  prefixIcon: const Icon(Icons.person_outline_rounded, color: SymphonyTheme.textSecondary, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accent.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 18),

              // Instance Name Field
              const Text(
                'APP TITLE / INSTANCE NAME',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: SymphonyTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _instanceController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "e.g. Jett's Symphony",
                  hintStyle: const TextStyle(color: SymphonyTheme.textMuted),
                  filled: true,
                  fillColor: const Color(0xFF282828),
                  prefixIcon: const Icon(Icons.music_note_rounded, color: SymphonyTheme.textSecondary, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accent.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),

              // Quick presets
              if (enteredName.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildPresetChip("$enteredName's Symphony"),
                    _buildPresetChip("$enteredName's Studio"),
                    _buildPresetChip("$enteredName's Music"),
                    _buildPresetChip("Symphony"),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Software & Updates
              const Text(
                'SOFTWARE & UPDATES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: SymphonyTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _buildUpdateSection(context, ref, accent),
              const SizedBox(height: 18),

              // Save Button
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await ref.read(personalizationProvider.notifier).updateProfile(
                          userName: _nameController.text,
                          instanceName: _instanceController.text,
                        );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF282828),
                          content: Text(
                            'Personalized as "${ref.read(personalizationProvider).displayTitle}" ✨',
                            style: const TextStyle(color: Colors.white),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Save & Personalize',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label) {
    final isSelected = _instanceController.text == label;
    final accent = ref.watch(accentThemeProvider);

    return InkWell(
      onTap: () => setState(() => _instanceController.text = label),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? accent.primary.withOpacity(0.2) : const Color(0xFF282828),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accent.primary : const Color(0xFF404040),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? accent.primary : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateSection(BuildContext context, WidgetRef ref, SymphonyAccent accent) {
    final updateState = ref.watch(appUpdateProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      child: Row(
        children: [
          Icon(
            updateState.hasUpdate
                ? Icons.system_update_rounded
                : Icons.check_circle_outline_rounded,
            size: 20,
            color: updateState.hasUpdate ? Colors.white : SymphonyTheme.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Symphony v${AppUpdateNotifier.currentVersion}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  updateState.isChecking
                      ? 'Checking GitHub Releases...'
                      : updateState.hasUpdate
                          ? 'Update ${updateState.latestRelease?.tagName} available'
                          : 'Symphony is up to date',
                  style: TextStyle(
                    color: updateState.hasUpdate ? Colors.white70 : SymphonyTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (updateState.hasUpdate && updateState.latestRelease != null)
            ElevatedButton(
              onPressed: () {
                AppUpdateDialog.show(context, updateState.latestRelease!);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
              child: const Text('Update', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            )
          else
            TextButton(
              onPressed: updateState.isChecking
                  ? null
                  : () => ref.read(appUpdateProvider.notifier).checkForUpdates(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                foregroundColor: Colors.white70,
              ),
              child: updateState.isChecking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Check', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
