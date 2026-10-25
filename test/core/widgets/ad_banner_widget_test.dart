import 'package:client/core/widgets/ad_banner_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('hides while the ad-free window is open', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ads_free_until_ms':
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AdBannerWidget())),
    );
    await tester.pump();

    expect(find.byType(AdWidget), findsNothing);
  });
}
