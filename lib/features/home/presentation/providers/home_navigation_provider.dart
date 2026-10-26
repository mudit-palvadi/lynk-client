import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum HomeDestination { send, receive, activity }

final homeNavigationProvider =
    NotifierProvider<HomeNavigation, HomeDestination>(HomeNavigation.new);

class HomeNavigation extends Notifier<HomeDestination> {
  @override
  HomeDestination build() => HomeDestination.send;

  void select(HomeDestination destination) => state = destination;
}

final homeVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version}+${info.buildNumber}';
});

final diagnosticTapProvider = NotifierProvider<DiagnosticTaps, int>(
  DiagnosticTaps.new,
);

class DiagnosticTaps extends Notifier<int> {
  @override
  int build() => 0;

  bool registerTap() {
    state = (state + 1) % 7;
    return state == 0;
  }
}
