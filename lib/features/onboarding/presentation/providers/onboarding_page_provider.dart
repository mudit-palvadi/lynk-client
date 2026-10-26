import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Intro progress is temporary; completion remains in onboardingProvider.
final onboardingPageProvider =
    NotifierProvider.autoDispose<OnboardingPage, int>(OnboardingPage.new);

class OnboardingPage extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    if (index >= 0 && index < 3) {
      state = index;
    }
  }
}
