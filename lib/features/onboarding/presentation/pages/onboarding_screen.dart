import 'package:client/core/theme/app_theme.dart';
import 'package:client/core/utils/app_links.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_page_provider.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();

  final List<_OnboardingPageData> _pages = const [
    _OnboardingPageData(
      title: 'Send without an account.',
      description: 'Choose files. Share a QR or code. No account needed.',
    ),
    _OnboardingPageData(
      title: 'Have a QR or code?',
      description: 'Open Receive to scan the sender QR or enter the code.',
    ),
    _OnboardingPageData(
      title: 'Let the sender start.',
      description:
          'Show the receiving QR. The sender scans it and chooses files. Keep this screen open.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(onboardingProvider.notifier).completeOnboarding();
  }

  void _next(int index) {
    if (index == _pages.length - 1) {
      _finish();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(index + 1);
    } else {
      _controller.animateToPage(
        index + 1,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(AppLinks.privacyPolicyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open the privacy policy page.'),
            backgroundColor: AppTheme.of(context).error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(onboardingPageProvider);
    return Scaffold(
      body: SafeArea(
        child: Align(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 500;
                final action = ElevatedButton(
                  onPressed: () => _next(currentIndex),
                  child: Text(
                    currentIndex == _pages.length - 1 ? 'Get Started' : 'Next',
                  ),
                );
                final privacy = TextButton(
                  onPressed: _openPrivacyPolicy,
                  child: const Text('Privacy Policy'),
                );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'lynk',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.of(context).textPrimary,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                          Visibility(
                            visible: currentIndex < _pages.length - 1,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: TextButton(
                              onPressed: _finish,
                              child: const Text('Skip'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: _pages.length,
                        onPageChanged: ref
                            .read(onboardingPageProvider.notifier)
                            .select,
                        itemBuilder: (context, index) => SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TransferIllustration(
                                page: index,
                                compact: compact,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                _pages[index].title,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _pages[index].description,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Internet required.',
                                style: TextStyle(
                                  color: AppTheme.of(context).textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                      child: Column(
                        children: [
                          Semantics(
                            label:
                                'Page ${currentIndex + 1} of ${_pages.length}',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _pages.length,
                                (index) => Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: index == currentIndex
                                        ? AppTheme.of(context).primary
                                        : AppTheme.of(context).border,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (compact)
                            Row(
                              children: [
                                Expanded(child: privacy),
                                const SizedBox(width: 12),
                                Expanded(child: action),
                              ],
                            )
                          else ...[
                            SizedBox(width: double.infinity, child: action),
                            const SizedBox(height: 4),
                            privacy,
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final String title;
  final String description;
  const _OnboardingPageData({required this.title, required this.description});
}

class _TransferIllustration extends StatelessWidget {
  const _TransferIllustration({required this.page, required this.compact});

  final int page;
  final bool compact;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: compact ? 144 : 220),
    child: Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Device(
            icon: page == 0
                ? Icons.insert_drive_file_outlined
                : Icons.qr_code_2,
            label: page == 0 ? 'Sender' : 'Receiver',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              page == 0
                  ? Icons.arrow_forward_rounded
                  : Icons.arrow_back_rounded,
              color: AppTheme.of(context).primary,
              size: 24,
            ),
          ),
          _Device(
            icon: page == 1 ? Icons.pin_outlined : Icons.phone_android_rounded,
            label: page == 0 ? 'Receiver' : 'Sender',
          ),
        ],
      ),
    ),
  );
}

class _Device extends StatelessWidget {
  const _Device({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Flexible(
    child: Container(
      width: 112,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.of(context).cardBg,
        border: Border.all(color: AppTheme.of(context).border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppTheme.of(context).primary),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.of(context).textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}
