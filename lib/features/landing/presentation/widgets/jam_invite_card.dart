import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/symphony_theme.dart';
import '../../../jam/domain/jam_invite.dart';

/// Top of the landing page when it was opened from a Jam invite
/// (`?jam=<code>`): who's invited where, and how to get in: open the app
/// (Android), or install it first.
class JamInviteCard extends StatelessWidget {
  final String code;
  final VoidCallback onDownload;

  const JamInviteCard({super.key, required this.code, required this.onDownload});

  bool get _onAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 4-digit codes are Jams on the host's Wi-Fi.
  bool get _sameWifi => RegExp(r'^\d{4}$').hasMatch(code);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: SymphonyTheme.recapGradients.first,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.groups_rounded, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'You’re invited to a Jam',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _sameWifi
                ? 'Everyone in a Jam hears the same songs at the same time. This one is on the host’s Wi-Fi, so join from the same network.'
                : 'Everyone in a Jam hears the same songs at the same time, wherever they are.',
            style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 18),
          SelectableText(
            code,
            style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (_onAndroid)
                _Button(
                  label: 'Open in Symphony',
                  icon: Icons.open_in_new_rounded,
                  filled: true,
                  onTap: () => launchUrl(JamInvite.appLink(code), webOnlyWindowName: '_self'),
                ),
              _Button(
                label: _onAndroid ? 'Get Symphony for Android' : 'Download Symphony',
                icon: Icons.download_rounded,
                filled: !_onAndroid,
                onTap: onDownload,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _onAndroid
                ? 'New to Symphony? Install it, open it once, then come back here and tap Open in Symphony. '
                    'Or open Jam in the app and enter $code.'
                : 'Install Symphony, open Jam and enter $code.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _Button({required this.label, required this.icon, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(500));
    const padding = EdgeInsets.symmetric(horizontal: 20);
    if (filled) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: SymphonyTheme.obsidian,
          minimumSize: const Size(0, 48),
          padding: padding,
          shape: shape,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white70),
        minimumSize: const Size(0, 48),
        padding: padding,
        shape: shape,
      ),
    );
  }
}
