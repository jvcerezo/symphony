import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/audio_player_providers.dart';

/// Desktop player volume: the slider level plus a mute toggle that remembers
/// the level. Shared by the desktop player bar and keyboard shortcuts so both
/// always show the same value.
class VolumeState {
  final double level;
  final bool muted;

  const VolumeState({this.level = 1.0, this.muted = false});

  /// Volume actually applied to the player.
  double get effective => muted ? 0.0 : level;
}

class VolumeNotifier extends StateNotifier<VolumeState> {
  VolumeNotifier(this._apply) : super(const VolumeState());

  final Future<void> Function(double volume) _apply;

  /// Sets the level (clamped to 0..1) and unmutes.
  void setLevel(double level) {
    final clamped = (level.clamp(0.0, 1.0) * 100).roundToDouble() / 100;
    state = VolumeState(level: clamped);
    _apply(state.effective);
  }

  /// Raises or lowers the audible volume by [delta]; unmutes.
  void step(double delta) => setLevel(state.effective + delta);

  void toggleMute() {
    state = VolumeState(level: state.level, muted: !state.muted);
    _apply(state.effective);
  }
}

final volumeProvider = StateNotifierProvider<VolumeNotifier, VolumeState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return VolumeNotifier(handler.setVolume);
});
