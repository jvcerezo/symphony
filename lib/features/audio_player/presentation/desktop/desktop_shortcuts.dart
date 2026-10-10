import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../metadata_search/presentation/controllers/search_focus_provider.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/navigation_history_provider.dart';
import 'desktop_volume_provider.dart';

// ---------------------------------------------------------------- intents

class TogglePlayPauseIntent extends Intent {
  const TogglePlayPauseIntent();
}

class SkipTrackIntent extends Intent {
  final bool forward;
  const SkipTrackIntent({required this.forward});
}

class SeekRelativeIntent extends Intent {
  final Duration offset;
  const SeekRelativeIntent(this.offset);
}

class ChangeVolumeIntent extends Intent {
  final double delta;
  const ChangeVolumeIntent(this.delta);
}

class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

class NavigateHistoryIntent extends Intent {
  final bool forward;
  const NavigateHistoryIntent({required this.forward});
}

class ShowShortcutsHelpIntent extends Intent {
  const ShowShortcutsHelpIntent();
}

class LeaveTextFieldIntent extends Intent {
  const LeaveTextFieldIntent();
}

// ---------------------------------------------------------------- bindings

/// One row of the "?" help overlay.
class ShortcutDescription {
  final String keys;
  final String action;
  const ShortcutDescription(this.keys, this.action);
}

/// Shown in the help overlay; keep in sync with [desktopShortcutBindings].
const List<ShortcutDescription> desktopShortcutDescriptions = [
  ShortcutDescription('Space', 'Play / pause'),
  ShortcutDescription('Ctrl + →', 'Next track'),
  ShortcutDescription('Ctrl + ←', 'Previous track'),
  ShortcutDescription('Shift + →', 'Seek forward 10 s'),
  ShortcutDescription('Shift + ←', 'Seek back 10 s'),
  ShortcutDescription('Ctrl + ↑', 'Volume up'),
  ShortcutDescription('Ctrl + ↓', 'Volume down'),
  ShortcutDescription('Ctrl + F  or  /', 'Search'),
  ShortcutDescription('Alt + ←', 'Back'),
  ShortcutDescription('Alt + →', 'Forward'),
  ShortcutDescription('Esc', 'Close dialog / leave text field'),
  ShortcutDescription('?', 'Show this list'),
];

const Duration _seekStep = Duration(seconds: 10);
const Duration _seekBackStep = Duration(seconds: -10);
const double _volumeStep = 0.1;

const Map<ShortcutActivator, Intent> desktopShortcutBindings = {
  SingleActivator(LogicalKeyboardKey.space): TogglePlayPauseIntent(),
  SingleActivator(LogicalKeyboardKey.arrowRight, control: true): SkipTrackIntent(forward: true),
  SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): SkipTrackIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): SeekRelativeIntent(_seekStep),
  SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): SeekRelativeIntent(_seekBackStep),
  SingleActivator(LogicalKeyboardKey.arrowUp, control: true): ChangeVolumeIntent(_volumeStep),
  SingleActivator(LogicalKeyboardKey.arrowDown, control: true): ChangeVolumeIntent(-_volumeStep),
  SingleActivator(LogicalKeyboardKey.keyF, control: true): FocusSearchIntent(),
  CharacterActivator('/'): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): NavigateHistoryIntent(forward: false),
  SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): NavigateHistoryIntent(forward: true),
  CharacterActivator('?'): ShowShortcutsHelpIntent(),
  SingleActivator(LogicalKeyboardKey.escape): LeaveTextFieldIntent(),
};

// ---------------------------------------------------------------- commands

/// What the shortcuts do. Separate from the bindings so widget tests can
/// verify key → command wiring without a real audio player.
abstract class PlayerKeyboardCommands {
  Future<void> togglePlayPause();
  Future<void> skip({required bool forward});
  Future<void> seekBy(Duration offset);
  void changeVolume(double delta);
  void openSearch();
  void navigateHistory({required bool forward});
}

/// Production commands backed by the audio handler and Riverpod state.
class RiverpodPlayerKeyboardCommands implements PlayerKeyboardCommands {
  RiverpodPlayerKeyboardCommands(this.ref);

  final WidgetRef ref;

  @override
  Future<void> togglePlayPause() async {
    final handler = ref.read(audioHandlerProvider);
    if (handler.playbackState.value.playing) {
      await handler.pause();
    } else if (handler.mediaItem.value != null) {
      await handler.play();
    }
  }

  @override
  Future<void> skip({required bool forward}) {
    final handler = ref.read(audioHandlerProvider);
    return forward ? handler.skipToNext() : handler.skipToPrevious();
  }

  @override
  Future<void> seekBy(Duration offset) async {
    final handler = ref.read(audioHandlerProvider);
    if (handler.mediaItem.value == null) return;
    final duration = handler.mediaItem.value?.duration;
    var target = handler.playbackState.value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && duration > Duration.zero && target > duration) target = duration;
    await handler.seek(target);
  }

  @override
  void changeVolume(double delta) => ref.read(volumeProvider.notifier).step(delta);

  @override
  void openSearch() {
    final node = ref.read(searchFieldFocusNodeProvider);
    if (ref.read(activeNavTabProvider) == 'search' && node.context != null) {
      node.requestFocus();
      return;
    }
    ref.read(activeNavTabProvider.notifier).state = 'search';
    // The Search view mounts on the next frame (scheduled by the tab change).
    WidgetsBinding.instance.addPostFrameCallback((_) => node.requestFocus());
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void navigateHistory({required bool forward}) {
    final nav = ref.read(navigationHistoryProvider.notifier);
    forward ? nav.goForward(ref) : nav.goBack(ref);
  }
}

// ---------------------------------------------------------------- widget

/// Installs the desktop keyboard shortcuts around [child].
///
/// Shortcuts never fire while a text field has focus (typing a space or
/// using Ctrl/Shift+arrows edits text as usual); Esc leaves the field and
/// returns focus here. Space also yields to a focused button/control so
/// keyboard activation keeps working. Dialogs live in the navigator overlay,
/// outside this subtree, so shortcuts are inactive while one is open and Esc
/// closes it via Flutter's default DismissIntent.
class DesktopShortcuts extends ConsumerStatefulWidget {
  final Widget child;

  /// Override for tests; defaults to [RiverpodPlayerKeyboardCommands].
  final PlayerKeyboardCommands? commands;

  const DesktopShortcuts({super.key, required this.child, this.commands});

  @override
  ConsumerState<DesktopShortcuts> createState() => _DesktopShortcutsState();
}

class _DesktopShortcutsState extends ConsumerState<DesktopShortcuts> {
  final FocusNode _shellFocus = FocusNode(debugLabel: 'DesktopShortcuts');
  late PlayerKeyboardCommands _commands;

  @override
  void initState() {
    super.initState();
    _commands = widget.commands ?? RiverpodPlayerKeyboardCommands(ref);
    FocusManager.instance.addListener(_reclaimOrphanedFocus);
  }

  /// When the focused widget below us is removed (e.g. leaving the Search
  /// tab while its field is focused) focus falls back to the route's scope,
  /// which sits above this widget, and key events would no longer reach the
  /// shortcuts. Pull focus back onto the shell in that case.
  void _reclaimOrphanedFocus() {
    if (!mounted || _shellFocus.context == null) return;
    final primary = FocusManager.instance.primaryFocus;
    final orphaned = primary == null || (primary is FocusScopeNode && primary == _shellFocus.enclosingScope);
    if (orphaned && !_shellFocus.hasPrimaryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = FocusManager.instance.primaryFocus;
        if (current == null || (current is FocusScopeNode && current == _shellFocus.enclosingScope)) {
          _shellFocus.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(DesktopShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commands != widget.commands) {
      _commands = widget.commands ?? RiverpodPlayerKeyboardCommands(ref);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reclaimOrphanedFocus);
    _shellFocus.dispose();
    super.dispose();
  }

  static bool _isTextInputFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  /// True when focus is on the shell itself (nothing more specific focused).
  bool _isShellFocused() {
    final primary = FocusManager.instance.primaryFocus;
    return primary == null || primary == _shellFocus || primary is FocusScopeNode;
  }

  bool _canUseGlobalShortcut() => !_isTextInputFocused();

  Future<void> _showHelp() {
    return showDialog<void>(
      context: context,
      builder: (_) => const ShortcutsHelpDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: desktopShortcutBindings,
      child: Actions(
        actions: <Type, Action<Intent>>{
          TogglePlayPauseIntent: _GuardedAction<TogglePlayPauseIntent>(
            enabled: () => _canUseGlobalShortcut() && _isShellFocused(),
            onInvoke: (_) => _commands.togglePlayPause(),
          ),
          SkipTrackIntent: _GuardedAction<SkipTrackIntent>(
            enabled: _canUseGlobalShortcut,
            onInvoke: (i) => _commands.skip(forward: i.forward),
          ),
          SeekRelativeIntent: _GuardedAction<SeekRelativeIntent>(
            enabled: _canUseGlobalShortcut,
            onInvoke: (i) => _commands.seekBy(i.offset),
          ),
          ChangeVolumeIntent: _GuardedAction<ChangeVolumeIntent>(
            enabled: _canUseGlobalShortcut,
            onInvoke: (i) => _commands.changeVolume(i.delta),
          ),
          FocusSearchIntent: _GuardedAction<FocusSearchIntent>(
            enabled: _canUseGlobalShortcut,
            onInvoke: (_) => _commands.openSearch(),
          ),
          NavigateHistoryIntent: _GuardedAction<NavigateHistoryIntent>(
            enabled: _canUseGlobalShortcut,
            onInvoke: (i) => _commands.navigateHistory(forward: i.forward),
          ),
          ShowShortcutsHelpIntent: _GuardedAction<ShowShortcutsHelpIntent>(
            enabled: _canUseGlobalShortcut,
            onInvoke: (_) => _showHelp(),
          ),
          LeaveTextFieldIntent: _GuardedAction<LeaveTextFieldIntent>(
            enabled: _isTextInputFocused,
            onInvoke: (_) => _shellFocus.requestFocus(),
          ),
        },
        child: Focus(
          focusNode: _shellFocus,
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }
}

/// An action that is only enabled (and therefore only consumes the key)
/// when [enabled] returns true; otherwise the key event keeps propagating.
class _GuardedAction<T extends Intent> extends Action<T> {
  _GuardedAction({required this.enabled, required this.onInvoke});

  final bool Function() enabled;
  final Object? Function(T intent) onInvoke;

  @override
  bool isEnabled(T intent) => enabled();

  @override
  Object? invoke(T intent) => onInvoke(intent);
}

// ---------------------------------------------------------------- help overlay

/// "?" overlay listing every desktop shortcut.
class ShortcutsHelpDialog extends StatelessWidget {
  const ShortcutsHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SymphonyTheme.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        'Keyboard shortcuts',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in desktopShortcutDescriptions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.action,
                          style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: SymphonyTheme.cardHover,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s.keys,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
