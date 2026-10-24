import 'package:client/features/onboarding/presentation/providers/home_tutorial_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerFor(Map<String, Object> values) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    // Keep the auto-disposed notifier alive across the awaits below.
    container.listen(homeTutorialProvider, (_, _) {});
    return container;
  }

  test('a fresh install has not seen the walkthrough', () async {
    final container = await containerFor({});

    expect(container.read(homeTutorialProvider), isFalse);
  });

  test('finishing the walkthrough is remembered on the device', () async {
    final container = await containerFor({});
    final prefs = container.read(sharedPreferencesProvider);

    await container.read(homeTutorialProvider.notifier).complete();

    expect(container.read(homeTutorialProvider), isTrue);
    expect(prefs.getBool(HomeTutorialNotifier.key), isTrue);
  });

  test('a remembered walkthrough stays gone on the next launch', () async {
    final container = await containerFor({HomeTutorialNotifier.key: true});

    expect(container.read(homeTutorialProvider), isTrue);
  });
}
