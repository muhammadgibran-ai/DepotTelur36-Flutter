import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/screens/auth/splash_screen.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e, st) {
    debugPrint('Firebase initialization skipped: $e\n$st');
  }

  runApp(const DepotTelur36App());
}

/// Root widget aplikasi DepotTelur36 (Offline-First POS & Manajemen Stok).
class DepotTelur36App extends StatefulWidget {
  const DepotTelur36App({
    super.key,
    this.authViewModelOverride,
    this.splashDelay = const Duration(milliseconds: 1200),
  });

  final AuthViewModel? authViewModelOverride;
  final Duration splashDelay;

  @override
  State<DepotTelur36App> createState() => _DepotTelur36AppState();
}

class _DepotTelur36AppState extends State<DepotTelur36App> {
  SyncService? _syncService;
  InventoryRepository? _inventoryRepository;
  AuthViewModel? _ownedAuthViewModel;

  @override
  void initState() {
    super.initState();
    if (widget.authViewModelOverride == null) {
      final hasFirebase = Firebase.apps.isNotEmpty;
      final db = DatabaseHelper.instance;
      final syncService = SyncService(dbHelper: db);
      final inventoryRepository = InventoryRepository(
        dbHelper: db,
        syncService: syncService,
      );
      if (hasFirebase) {
        unawaited(
          inventoryRepository.initialize().catchError((Object e) {
            debugPrint('Inventory sync initialization deferred: $e');
          }),
        );
      }

      final authRepository = AuthRepository(
        dbHelper: db,
        syncService: hasFirebase ? syncService : null,
      );

      _syncService = syncService;
      _inventoryRepository = inventoryRepository;
      _ownedAuthViewModel = AuthViewModel(repository: authRepository);
    }
  }

  @override
  void dispose() {
    _ownedAuthViewModel?.dispose();
    _inventoryRepository?.dispose();
    _syncService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overrideVm = widget.authViewModelOverride;

    final app = MaterialApp(
      title: 'DepotTelur36',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashScreen(minimumDuration: widget.splashDelay),
    );

    if (overrideVm != null) {
      return ChangeNotifierProvider<AuthViewModel>.value(
        value: overrideVm,
        child: app,
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncService>.value(value: _syncService!),
        Provider<InventoryRepository>.value(value: _inventoryRepository!),
        ChangeNotifierProvider<AuthViewModel>.value(value: _ownedAuthViewModel!),
      ],
      child: app,
    );
  }
}
