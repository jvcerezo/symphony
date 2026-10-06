import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersonalizationState {
  final String instanceId;
  final String userName;
  final String instanceName;
  final bool isLoaded;

  const PersonalizationState({
    this.instanceId = '',
    this.userName = '',
    this.instanceName = 'Symphony',
    this.isLoaded = false,
  });

  String get displayName => userName.isNotEmpty ? userName : 'Listener';
  String get displayTitle => instanceName.isNotEmpty ? instanceName : 'Symphony';

  PersonalizationState copyWith({
    String? instanceId,
    String? userName,
    String? instanceName,
    bool? isLoaded,
  }) {
    return PersonalizationState(
      instanceId: instanceId ?? this.instanceId,
      userName: userName ?? this.userName,
      instanceName: instanceName ?? this.instanceName,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class PersonalizationNotifier extends StateNotifier<PersonalizationState> {
  static const _instanceIdKey = 'symphony_instance_id';
  static const _userNameKey = 'symphony_user_name';
  static const _instanceNameKey = 'symphony_instance_name';

  PersonalizationNotifier() : super(const PersonalizationState()) {
    _loadFromPreferences();
  }

  static Future<String> getOrCreateInstanceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_instanceIdKey);
      if (id == null || id.isEmpty || id == 'inst_default') {
        final rand = Random().nextInt(900000) + 100000;
        id = 'inst_${DateTime.now().millisecondsSinceEpoch}_$rand';
        await prefs.setString(_instanceIdKey, id);
      }
      return id;
    } catch (_) {
      final rand = Random().nextInt(900000) + 100000;
      return 'inst_${DateTime.now().millisecondsSinceEpoch}_$rand';
    }
  }

  Future<void> _loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var instanceId = prefs.getString(_instanceIdKey);
      if (instanceId == null || instanceId.isEmpty || instanceId == 'inst_default') {
        final rand = Random().nextInt(900000) + 100000;
        instanceId = 'inst_${DateTime.now().millisecondsSinceEpoch}_$rand';
        await prefs.setString(_instanceIdKey, instanceId);
      }

      final savedUser = prefs.getString(_userNameKey) ?? '';
      final savedInstance = prefs.getString(_instanceNameKey) ??
          (savedUser.isNotEmpty ? "$savedUser's Symphony" : 'Symphony');

      state = PersonalizationState(
        instanceId: instanceId,
        userName: savedUser,
        instanceName: savedInstance,
        isLoaded: true,
      );
    } catch (_) {
      state = state.copyWith(isLoaded: true);
    }
  }

  Future<void> updateProfile({required String userName, required String instanceName}) async {
    final cleanUser = userName.trim();
    final cleanInstance = instanceName.trim().isNotEmpty
        ? instanceName.trim()
        : (cleanUser.isNotEmpty ? "$cleanUser's Symphony" : 'Symphony');

    state = state.copyWith(
      userName: cleanUser,
      instanceName: cleanInstance,
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userNameKey, cleanUser);
      await prefs.setString(_instanceNameKey, cleanInstance);
    } catch (_) {}
  }
}

final personalizationProvider =
    StateNotifierProvider<PersonalizationNotifier, PersonalizationState>((ref) {
  return PersonalizationNotifier();
});
