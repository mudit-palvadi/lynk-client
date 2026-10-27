import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ad_consent_provider.dart';

/// Consent is requested only after the Play update gate admits the app and an
/// activity is mounted. Consent never blocks file-transfer navigation.
class AdConsentGate extends ConsumerStatefulWidget {
  const AdConsentGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AdConsentGate> createState() => _AdConsentGateState();
}

class _AdConsentGateState extends ConsumerState<AdConsentGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(adConsentProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
