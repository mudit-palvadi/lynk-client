import 'package:client/features/onboarding/presentation/providers/onboarding_page_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('temporary onboarding page state', () {
    test('starts at Send and accepts all three pages', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(onboardingPageProvider, (_, _) {});
      addTearDown(subscription.close);
      expect(container.read(onboardingPageProvider), 0);
      final pages = container.read(onboardingPageProvider.notifier);
      for (final index in [1, 2, 0]) {
        pages.select(index);
        expect(container.read(onboardingPageProvider), index);
      }
    });

    test('ignores out-of-range page events', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(onboardingPageProvider, (_, _) {});
      addTearDown(subscription.close);
      final pages = container.read(onboardingPageProvider.notifier);
      pages.select(1);
      pages.select(-1);
      pages.select(3);
      expect(container.read(onboardingPageProvider), 1);
    });

    test('resets when the intro is no longer observed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(onboardingPageProvider, (_, _) {});
      container.read(onboardingPageProvider.notifier).select(2);
      subscription.close();
      await container.pump();
      expect(container.read(onboardingPageProvider), 0);
    });
  });
}
