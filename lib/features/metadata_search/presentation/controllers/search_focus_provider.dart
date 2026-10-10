import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Focus node of the Search tab's query field, so other widgets (e.g. the
/// desktop Ctrl+F / "/" shortcut) can move the caret into it.
final searchFieldFocusNodeProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'SearchField');
  ref.onDispose(node.dispose);
  return node;
});
