// opview — openpilot onroad UI
// entry point: landscape, immersive, go

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // landscape only, like the real thing
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // immersive fullscreen — no status bar, no nav bar
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // keep screen on: handled via FLAG_KEEP_SCREEN_ON in MainActivity.kt

  runApp(const OpviewApp());
}
