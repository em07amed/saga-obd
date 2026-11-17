import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'maintenance/maintenance.dart';
import 'obd/bt_channel.dart';
import 'obd/obd_service.dart';
import 'settings.dart';
import 'trips/trip_db.dart';
import 'trips/trip_recorder.dart';
import 'ui/dashboard_page.dart';
import 'ui/maintenance_page.dart';
import 'ui/readings_page.dart';
import 'ui/settings_page.dart';
import 'ui/trips_page.dart';

/// Simple service locator; the app is small enough not to need a DI package.
class App {
  static late final AppSettings settings;
  static late final ObdService obd;
  static late final TripDb db;
  static late final TripRecorder trips;
  static late final MaintenanceService maintenance;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  App.db = TripDb();
  await App.db.open();
  App.settings = AppSettings();
  await App.settings.load(App.db);
  App.obd = ObdService(BtChannel(), App.settings);
  App.trips = TripRecorder(App.obd, App.db, App.settings);
  App.maintenance =
      MaintenanceService(App.db, App.settings, App.obd, App.trips);
  await App.maintenance.load();
  runApp(const CarObdApp());
}

class CarObdApp extends StatelessWidget {
  const CarObdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.settings,
      builder: (context, _) => MaterialApp(
      title: 'Car OBD',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: switch (App.settings.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomeShell(),
      ),
    );
  }

  static ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF006A60),
      brightness: b,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: dark ? scheme : scheme.copyWith(surface: Colors.white),
      scaffoldBackgroundColor: dark ? const Color(0xFF0F1514) : Colors.white,
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF1B2120) : const Color(0xFFF1F6F4),
        elevation: 0,
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    App.obd.addListener(_keepScreenOn);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  Future<void> _startup() async {
    await [Permission.bluetoothConnect].request();
    final loc = await Geolocator.checkPermission();
    if (loc == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    if (App.settings.autoConnect && App.settings.deviceAddress != null) {
      unawaited(App.obd.connect());
    }
  }

  void _keepScreenOn() {
    // Keep the display awake while connected so polling/trip logging continue.
    WakelockPlus.toggle(enable: App.obd.state != ObdState.disconnected);
  }

  @override
  void dispose() {
    App.obd.removeListener(_keepScreenOn);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      DashboardPage(),
      ReadingsPage(),
      TripsPage(),
      MaintenancePage(),
      SettingsPage(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'الداشبورد'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'القراءات'),
          NavigationDestination(icon: Icon(Icons.route), label: 'الرحلات'),
          NavigationDestination(icon: Icon(Icons.build), label: 'الصيانة'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
