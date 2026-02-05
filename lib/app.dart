// opview app shell
// dark theme, single screen, no navigation needed

import 'package:flutter/material.dart';
import 'package:opview/selfdrive/ui/ui_state.dart';
import 'package:opview/selfdrive/ui/onroad/augmented_road_view.dart';
import 'package:opview/services/connection_manager.dart';

class ScopeApp extends StatefulWidget {
  const ScopeApp({super.key});

  @override
  State<ScopeApp> createState() => _ScopeAppState();
}

class _ScopeAppState extends State<ScopeApp> with WidgetsBindingObserver {
  late final UIState _uiState;
  late final ConnectionManager _connectionManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uiState = UIState();
    _connectionManager = ConnectionManager(_uiState);
    _connectionManager.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // async cleanup — best-effort, State.dispose() is sync
    _connectionManager.dispose();
    _uiState.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[opview] app resumed, reconnecting');
      _connectionManager.reconnect();
    } else if (state == AppLifecycleState.paused) {
      debugPrint('[opview] app paused, stopping');
      _connectionManager.pause();
    }
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'opview',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: ListenableBuilder(
        listenable: _uiState,
        builder: (context, _) => AugmentedRoadView(
          uiState: _uiState,
          videoRenderer: _connectionManager.videoRenderer,
        ),
      ),
    );
  }
}
