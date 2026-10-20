import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Text shorter than this decodes faster in place than a background
/// isolate starts.
const _inlineBelow = 64 * 1024;

/// [jsonDecode] for text that can be large, such as a saved library or a
/// listening history: decoded on a background isolate, so the screen keeps
/// drawing meanwhile. Small text decodes in place. On the web, in place.
Future<Object?> decodeJsonInBackground(String text) =>
    text.length < _inlineBelow ? Future.value(jsonDecode(text)) : compute(_decode, text);

Object? _decode(String text) => jsonDecode(text);
