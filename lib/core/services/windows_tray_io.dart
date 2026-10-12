// windows_tray_io.dart
import 'dart:async';
import 'dart:developer' as developer;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

_WindowsTray? _tray;

/// Windows only: a tray icon with playback controls, and closing the window
/// hides it to the tray (music keeps playing) when [closeToTray] is on.
/// Quit from the tray menu exits for real.
Future<void> initWindowsTray({required AudioHandler handler, required bool closeToTray}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows || _tray != null) return;
  try {
    final tray = _WindowsTray(handler)..closeToTray = closeToTray;
    await tray.init();
    _tray = tray;
  } catch (e, st) {
    // Without the tray the window still closes normally.
    developer.log('Tray setup failed', error: e, stackTrace: st, name: 'Tray');
  }
}

/// Whether the close button hides to the tray (true) or quits (false).
void setCloseToTray(bool value) => _tray?.closeToTray = value;

class _WindowsTray with TrayListener, WindowListener {
  final AudioHandler _handler;
  bool closeToTray = true;
  bool? _menuShowsPlaying;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<MediaItem?>? _itemSub;

  _WindowsTray(this._handler);

  Future<void> init() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await trayManager.setIcon('assets/images/tray_icon.ico');
    await trayManager.setToolTip('Symphony');
    trayManager.addListener(this);
    await _updateMenu(playing: false);

    _stateSub = _handler.playbackState.listen((s) {
      if (s.playing != _menuShowsPlaying) unawaited(_updateMenu(playing: s.playing));
    });
    _itemSub = _handler.mediaItem.listen((item) {
      final tip = item == null ? 'Symphony' : '${item.title} — ${item.artist ?? ''} · Symphony';
      // Windows caps tray tooltips at 127 characters.
      unawaited(trayManager.setToolTip(tip.length > 120 ? '${tip.substring(0, 119)}…' : tip));
    });
  }

  Future<void> _updateMenu({required bool playing}) async {
    _menuShowsPlaying = playing;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Show Symphony'),
      MenuItem.separator(),
      MenuItem(key: 'toggle', label: playing ? 'Pause' : 'Play'),
      MenuItem(key: 'next', label: 'Next'),
      MenuItem(key: 'previous', label: 'Previous'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit Symphony'),
    ]));
  }

  Future<void> _showWindow() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await _stateSub?.cancel();
    await _itemSub?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (closeToTray) {
      unawaited(windowManager.hide());
    } else {
      unawaited(_quit());
    }
  }

  @override
  void onTrayIconMouseDown() => unawaited(_showWindow());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showWindow());
      case 'toggle':
        unawaited(_handler.playbackState.value.playing ? _handler.pause() : _handler.play());
      case 'next':
        unawaited(_handler.skipToNext());
      case 'previous':
        unawaited(_handler.skipToPrevious());
      case 'quit':
        unawaited(_quit());
    }
  }
}
