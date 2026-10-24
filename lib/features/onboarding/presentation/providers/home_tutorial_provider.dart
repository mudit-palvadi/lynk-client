import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'onboarding_provider.dart';

part 'home_tutorial_provider.g.dart';

/// Whether the home-screen walkthrough has already been shown.
///
/// It lives next to onboarding because it is the same idea: a one-time
/// introduction, remembered on the device so it does not come back on every
/// launch. Onboarding explains what the app is; this points at the four things
/// the home screen can do.
@riverpod
class HomeTutorialNotifier extends _$HomeTutorialNotifier {
  static const String key = 'has_seen_home_tutorial';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(key) ?? false;
  }

  /// Remembers that the walkthrough was finished or skipped.
  Future<void> complete() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(key, true);
    state = true;
  }
}
