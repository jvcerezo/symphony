import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Windows: closing the window hides Symphony to the tray and music keeps
/// playing. `main.dart` overrides it with the saved value.
final closeToTrayProvider = StateProvider<bool>((ref) => true);
