import 'package:client/core/theme/app_theme.dart';
import 'package:client/core/utils/app_links.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  final List<_OnboardingPageData> _pages = const [
    _OnboardingPageData(
      icon: Icons.bolt,
      title: 'Instant Transfers',
      description:
          'Transfer files cross-device without creating an account or logging in.',
    ),
    _OnboardingPageData(
      icon: Icons.cloud_upload_outlined,
      title: 'Direct-to-Cloud',
      description:
          'Files stream directly to secure R2 storage. No server proxying.',
    ),
    _OnboardingPageData(
      icon: Icons.qr_code_scanner,
      title: 'QR Connection',
      description:
          'Simply scan a QR code to connect and initiate transfers seamlessly.',
    ),
  ];

  void _finish() {
    ref.read(onboardingProvider.notifier).completeOnboarding();
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(AppLinks.privacyPolicyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the privacy policy page.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: _currentIndex < _pages.length - 1
                  ? TextButton(
                      onPressed: _finish,
                      child: const Text(
                        'Skip',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : const SizedBox(height: 48),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 100, color: AppTheme.primary),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.description,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SmoothPageIndicator(
              controller: _controller,
              count: _pages.length,
              effect: const ExpandingDotsEffect(
                activeDotColor: AppTheme.primary,
                dotColor: AppTheme.cardBg,
                dotHeight: 8,
                dotWidth: 8,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _openPrivacyPolicy,
              icon: const Icon(
                Icons.privacy_tip_outlined,
                size: 16,
                color: AppTheme.textSecondary,
              ),
              label: const Text(
                'Privacy Policy',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: ElevatedButton(
                onPressed: () {
                  if (_currentIndex == _pages.length - 1) {
                    _finish();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                child: Text(
                  _currentIndex == _pages.length - 1 ? 'Get Started' : 'Next',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}
