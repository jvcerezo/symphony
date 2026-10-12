import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/app_prefs.dart';
import '../../../core/theme/symphony_theme.dart';
import '../../../core/widgets/symphony_brand_logo.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../audio_player/presentation/controllers/navigation_history_provider.dart';
import '../../audio_player/presentation/widgets/import_playlist_dialog.dart';
import '../../settings/presentation/controllers/personalization_provider.dart';

/// False until the first-run walkthrough is finished or skipped.
/// `main.dart` overrides it with the saved value; it defaults to true so
/// tests and the web demo open straight on the player.
final onboardingCompleteProvider = StateProvider<bool>((ref) => true);

/// First-run walkthrough: welcome, name, accent color, then where to
/// start (import a playlist, search, or look around).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 4;
  int _step = 0;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: ref.read(personalizationProvider).userName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 1) _saveName();
    if (_step < _stepCount - 1) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  void _saveName() {
    final name = _nameController.text.trim();
    if (name == ref.read(personalizationProvider).userName) return;
    ref.read(personalizationProvider.notifier).updateProfile(userName: name);
  }

  Future<void> _finish({String? openTab}) async {
    _saveName();
    if (openTab != null) {
      ref.read(activeNavTabProvider.notifier).state = openTab;
      ref.read(navigationHistoryProvider.notifier).record(openTab, null);
    }
    await AppPrefs.setOnboardingDone();
    ref.read(onboardingCompleteProvider.notifier).state = true;
  }

  Future<void> _importFirst() async {
    await showDialog<void>(context: context, builder: (_) => const ImportPlaylistDialog());
    if (mounted) await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentThemeProvider);
    final isLast = _step == _stepCount - 1;

    return Scaffold(
      backgroundColor: SymphonyTheme.obsidian,
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => _finish(),
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (int i = 0; i < _stepCount; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 6),
                            width: i == _step ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i <= _step ? accent.primary : SymphonyTheme.cardActive,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        const Spacer(),
                        if (!isLast)
                          TextButton(
                            onPressed: () => _finish(),
                            child: const Text('Skip', style: TextStyle(color: SymphonyTheme.textSecondary)),
                          ),
                      ],
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: switch (_step) {
                              0 => const _WelcomeStep(),
                              1 => _NameStep(controller: _nameController, onSubmitted: _next),
                              2 => const _AccentStep(),
                              _ => _StartStep(
                                  onImport: _importFirst,
                                  onSearch: () => _finish(openTab: 'search'),
                                  onExplore: () => _finish(),
                                ),
                            },
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (_step > 0)
                          TextButton(
                            onPressed: _back,
                            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                            child: const Text('Back', style: TextStyle(color: SymphonyTheme.textSecondary)),
                          ),
                        const Spacer(),
                        if (!isLast)
                          ElevatedButton(
                            onPressed: _next,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              minimumSize: const Size(140, 48),
                              shape: const StadiumBorder(),
                            ),
                            child: Text(
                              _step == 0 ? 'Get started' : 'Continue',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StepHeading(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 15, height: 1.4)),
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SymphonyBrandLogo(size: 64),
        SizedBox(height: 28),
        _StepHeading('Welcome to Symphony', 'Full-length songs, played and saved right on your device. No account needed.'),
        SizedBox(height: 28),
        _Feature(Icons.playlist_add_rounded, 'Bring your playlists', 'Paste a Spotify, YouTube or Apple Music link.'),
        _Feature(Icons.search_rounded, 'Find any song', 'Search by title or artist and press play.'),
        _Feature(Icons.download_for_offline_outlined, 'Listen offline', 'Download songs to play without a connection.'),
        _Feature(Icons.lyrics_outlined, 'Sing along', 'Lyrics that follow the song, plus a queue you can edit.'),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Feature(this.icon, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: SymphonyTheme.cardHover, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NameStep extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  const _NameStep({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading('What should we call you?', "We'll use it to greet you. You can leave it blank."),
        const SizedBox(height: 28),
        TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => onSubmitted(),
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Your name',
            hintStyle: const TextStyle(color: SymphonyTheme.textMuted),
            filled: true,
            fillColor: SymphonyTheme.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}

class _AccentStep extends ConsumerWidget {
  const _AccentStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(accentThemeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading('Pick your color', 'It lights up buttons, progress and highlights. Change it anytime.'),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final accent in SymphonyTheme.allAccents)
              Semantics(
                button: true,
                selected: accent.id == selected.id,
                label: accent.name,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => ref.read(accentThemeProvider.notifier).state = accent,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 132,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SymphonyTheme.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accent.id == selected.id ? accent.primary : SymphonyTheme.divider,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(gradient: accent.gradient, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            accent.name.split(' ').last,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StartStep extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onSearch;
  final VoidCallback onExplore;

  const _StartStep({required this.onImport, required this.onSearch, required this.onExplore});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeading('Add your first music', 'Your library starts empty. Pick a way in.'),
        const SizedBox(height: 28),
        _StartOption(
          icon: Icons.playlist_add_rounded,
          title: 'Import a playlist',
          body: 'Paste a link from Spotify, YouTube or Apple Music.',
          onTap: onImport,
        ),
        _StartOption(
          icon: Icons.search_rounded,
          title: 'Search for a song',
          body: 'Find something by title or artist.',
          onTap: onSearch,
        ),
        _StartOption(
          icon: Icons.explore_outlined,
          title: 'Look around first',
          body: 'Go to Home. You can import anytime.',
          onTap: onExplore,
        ),
      ],
    );
  }
}

class _StartOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _StartOption({required this.icon, required this.title, required this.body, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: SymphonyTheme.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(body, style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: SymphonyTheme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
