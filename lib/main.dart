import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:permission_handler/permission_handler.dart';

import 'alerts.dart';
import 'fuel/fuel_log.dart';
import 'maintenance/maintenance.dart';
import 'nav/nav_service.dart';
import 'radio/radio_service.dart';
import 'road/road_service.dart';
import 'obd/bt_channel.dart';
import 'obd/obd_service.dart';
import 'settings.dart';
import 'trips/trip_db.dart';
import 'trips/trip_recorder.dart';
import 'ui/call_overlay.dart';
import 'ui/dashboard_page.dart';
import 'ui/maintenance_page.dart';
import 'ui/readings_page.dart';
import 'ui/settings_page.dart';
import 'ui/sport_theme.dart';
import 'ui/trips_page.dart';
import 'l10n.dart';

/// Simple service locator; the app is small enough not to need a DI package.
class App {
  static late final AppSettings settings;
  static late final ObdService obd;
  static late final TripDb db;
  static late final TripRecorder trips;
  static late final MaintenanceService maintenance;
  static late final FuelLogService fuel;
  static late final AlertService alerts;
  static late final NavService nav;
  static late final RoadService road;
  static late final RadioService radio;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  App.db = TripDb();
  await App.db.open();
  App.settings = AppSettings();
  await App.settings.load(App.db);
  App.obd = ObdService(BtChannel(), App.settings);
  App.trips = TripRecorder(App.obd, App.db, App.settings);
  App.maintenance =
      MaintenanceService(App.db, App.settings, App.obd, App.trips);
  await App.maintenance.load();
  App.fuel = FuelLogService(App.db, App.settings, App.obd, App.trips);
  await App.fuel.load();
  App.nav = NavService(App.obd.bt);
  App.road = RoadService(App.obd.bt, App.settings, App.obd);
  App.radio = RadioService();
  await App.radio.init();
  App.alerts = AlertService(
      App.obd, App.settings, App.maintenance, App.obd.bt, App.road);
  runApp(CarObdApp());
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
      locale: Locale(App.settings.lang),
      supportedLocales: [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: switch (App.settings.themeMode) {
        'light' => ThemeMode.light,
        'dark' || 'sport' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      theme: _theme(Brightness.light),
      darkTheme: App.settings.themeMode == 'sport'
          ? sportTheme()
          : _theme(Brightness.dark),
      // Remount on language change so every tr() string is rebuilt.
      home: HomeShell(key: ValueKey(App.settings.lang)),
      // Incoming-call card and in-call bar over every screen.
      builder: (context, child) => CallOverlay(child: child!),
      ),
    );
  }

  static ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(0xFF006A60),
      brightness: b,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: dark ? scheme : scheme.copyWith(surface: Colors.white),
      scaffoldBackgroundColor: dark ? Color(0xFF0F1514) : Colors.white,
      cardTheme: CardThemeData(
        color: dark ? Color(0xFF1B2120) : Color(0xFFF1F6F4),
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
    await [Permission.bluetoothConnect, Permission.notification].request();
    final loc = await Geolocator.checkPermission();
    if (loc == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    if (App.settings.autoConnect && App.settings.deviceAddress != null) {
      unawaited(App.obd.connect());
    }
  }

  bool _keepAlive = false;

  /// While connected, run a foreground service so polling and trip logging
  /// continue with the screen off or another app in front.
  void _keepScreenOn() {
    final want = App.obd.state == ObdState.connected;
    if (want == _keepAlive) return;
    _keepAlive = want;
    if (want) {
      App.road.start();
      App.obd.bt
          .startKeepAlive('Car OBD', tr('بيسجّل الرحلة والقراءات'))
          .catchError((_) {});
    } else {
      App.road.stop();
      App.obd.bt.stopKeepAlive().catchError((_) {});
    }
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
        destinations: [
          NavigationDestination(icon: Icon(Icons.speed), label: tr('الداشبورد')),
          NavigationDestination(icon: Icon(Icons.list_alt), label: tr('القراءات')),
          NavigationDestination(icon: Icon(Icons.route), label: tr('الرحلات')),
          NavigationDestination(icon: Icon(Icons.build), label: tr('الصيانة')),
          NavigationDestination(icon: Icon(Icons.settings), label: tr('الإعدادات')),
        ],
      ),
    );
  }
}
