import 'package:client/core/theme/app_theme.dart';
import 'package:client/core/utils/app_links.dart';
import 'package:client/core/widgets/scrollable_fill.dart';
import 'package:client/features/onboarding/presentation/providers/onboarding_page_provider.dart';
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

  final List<_OnboardingPageData> _pages = const [
    _OnboardingPageData(
      icon: Icons.upload_outlined,
      title: 'Send files in a few taps',
      description:
          'Choose files, review your selection, then share a QR or six-digit code.',
      steps: ['Choose', 'Review', 'Share'],
      hint: 'No account needed. Internet required.',
    ),
    _OnboardingPageData(
      icon: Icons.download_outlined,
      title: 'Receive your way',
      description:
          'Start in Receive. Choose the option that matches what the sender has.',
      steps: ['Scan their QR', 'Enter their code', 'Show your receiving QR'],
      optionIcons: [Icons.qr_code_scanner, Icons.pin_outlined, Icons.qr_code_2],
      hint: 'Not sure who scans? The next page shows you.',
    ),
    _OnboardingPageData(
      icon: Icons.qr_code_2_outlined,
      title: 'Your QR. Their next move.',
      description:
          'You can invite someone to send files by showing your receiving QR.',
      steps: [
        'You: show your receiving QR.',
        'Sender: scan it in LynkShare, then choose files.',
      ],
      hint: 'Keep your screen open. Receiving starts automatically.',
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
    final currentIndex = ref.watch(onboardingPageProvider);
    return Scaffold(
      body: SafeArea(
        child: PageView.builder(
          controller: _controller,
          itemCount: _pages.length,
          onPageChanged: ref.read(onboardingPageProvider.notifier).select,
          itemBuilder: (context, index) {
            final page = _pages[index];
            final isCurrent = index == currentIndex;
            return Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ScrollableFill(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'lynk',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        if (isCurrent && index < _pages.length - 1)
                          TextButton(
                            onPressed: _finish,
                            child: const Text('Skip'),
                          )
                        else
                          const SizedBox(height: 48),
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withValues(alpha: 0.18),
                            AppTheme.secondary.withValues(alpha: 0.12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(page.icon, size: 64, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      page.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(page.description, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    for (var step = 0; step < page.steps.length; step++)
                      _InstructionTile(
                        number: step + 1,
                        text: page.steps[step],
                        icon: page.optionIcons.isEmpty
                            ? null
                            : page.optionIcons[step],
                      ),
                    const SizedBox(height: 8),
                    Text(
                      page.hint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    const Spacer(),
                    if (isCurrent) ...[
                      Semantics(
                        label: 'Page ${index + 1} of ${_pages.length}',
                        child: SmoothPageIndicator(
                          controller: _controller,
                          count: _pages.length,
                          effect: const ExpandingDotsEffect(
                            activeDotColor: AppTheme.primary,
                            dotColor: AppTheme.cardBg,
                            dotHeight: 8,
                            dotWidth: 8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _openPrivacyPolicy,
                        icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                        label: const Text('Privacy Policy'),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (index == _pages.length - 1) {
                              _finish();
                            } else {
                              _controller.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                          child: Text(
                            index == _pages.length - 1 ? 'Get Started' : 'Next',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String description;
  final List<String> steps;
  final String hint;
  final List<IconData> optionIcons;
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.description,
    required this.steps,
    required this.hint,
    this.optionIcons = const [],
  });
}

class _InstructionTile extends StatelessWidget {
  const _InstructionTile({required this.number, required this.text, this.icon});

  final int number;
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Icon(icon, color: AppTheme.secondary)
          else
            Text('$number', style: const TextStyle(color: AppTheme.secondary)),
          const SizedBox(width: 16),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
