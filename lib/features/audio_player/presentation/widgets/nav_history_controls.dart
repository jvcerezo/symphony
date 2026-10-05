import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/navigation_history_provider.dart';

class NavHistoryControls extends ConsumerWidget {
  final double size;

  const NavHistoryControls({super.key, this.size = 32});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navHistory = ref.watch(navigationHistoryProvider);
    final canBack = navHistory.canGoBack;
    final canForward = navHistory.canGoForward;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Back Button (<)
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: canBack ? const Color(0x7F000000) : const Color(0x2A000000),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.chevron_left,
              color: canBack ? Colors.white : Colors.white24,
              size: size * 0.68,
            ),
            tooltip: 'Go back',
            onPressed: canBack
                ? () => ref.read(navigationHistoryProvider.notifier).goBack(ref)
                : null,
          ),
        ),
        const SizedBox(width: 8),
        // Forward Button (>)
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: canForward ? const Color(0x7F000000) : const Color(0x2A000000),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.chevron_right,
              color: canForward ? Colors.white : Colors.white24,
              size: size * 0.68,
            ),
            tooltip: 'Go forward',
            onPressed: canForward
                ? () => ref.read(navigationHistoryProvider.notifier).goForward(ref)
                : null,
          ),
        ),
      ],
    );
  }
}
