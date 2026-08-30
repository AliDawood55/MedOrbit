import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

typedef CheckoutUrlLauncher = Future<bool> Function(Uri uri);

final checkoutUrlLauncherProvider = Provider<CheckoutUrlLauncher>((ref) {
  return (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
});
