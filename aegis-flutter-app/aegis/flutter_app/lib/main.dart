import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'sos/sos_handler.dart';
import 'sync/sync_service.dart';
import 'ui/admin_screen.dart';
import 'ui/auth_screens.dart';
import 'ui/contacts_screen.dart';
import 'ui/health_screen.dart';
import 'ui/home_screen.dart';
import 'ui/overlays.dart';
import 'ui/profile_screen.dart';
import 'ui/safety_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await notifications.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await SyncScheduler.init();
  runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const AegisApp()));
}

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AEGIS',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: context.select<AppState, ThemeMode>((s) => s.themeMode),
        home: const Root(),
      );
}

/// Puerta de entrada: nadie ve la app sin iniciar sesión.
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.onStartServices = _startServices;
    s.init();
  }

  // La app es usable aunque se rechacen permisos (SOS en pantalla y marcado manual siguen funcionando).
  Future<void> _startServices() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse, Permission.notification].request();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'band', channelName: 'Pulsera', channelDescription: 'Mantiene la conexión con la pulsera'),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
    );
    await FlutterForegroundTask.startService(notificationTitle: 'AEGIS activo', notificationText: 'Vigilando la pulsera');
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppState, AuthStage>((s) => s.stage);
    final Widget body = switch (stage) {
      AuthStage.loading => const _Splash(),
      AuthStage.loggedOut => const LoginScreen(),
      AuthStage.mustChange => const ForcedPasswordScreen(),
      AuthStage.mfaSetup => const MfaSetupScreen(),
      AuthStage.ready => const _Shell(),
    };
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey(stage), child: body));
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(borderRadius: BorderRadius.circular(26), child: Image.asset('assets/logo.png', width: 96, height: 96)),
            const SizedBox(height: 20),
            const CircularProgressIndicator.adaptive(),
          ]),
        ),
      );
}

class _Shell extends StatelessWidget {
  const _Shell();
  static const _user = <Widget>[HomeScreen(), HealthScreen(), SafetyScreen(), ContactsScreen(), ProfileScreen()];
  static const _admin = <Widget>[UsersScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pages = s.isAdmin ? _admin : _user;
    final tab = s.tab.clamp(0, pages.length - 1);
    final p = Pal.of(context);
    return Stack(children: [
      Scaffold(
        extendBody: true,
        body: Stack(children: [
          IndexedStack(index: tab, children: pages),
          if (s.rec.active && !s.rec.silent)
            Positioned(
              top: MediaQuery.of(context).padding.top + 4, right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AC.red, borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(CupertinoIcons.circle_fill, color: Colors.white, size: 9), SizedBox(width: 6), Text('REC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))]),
              ),
            ),
          if (s.banner != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16,
              child: Material(
                color: p.card, elevation: 6, borderRadius: BorderRadius.circular(16),
                child: Padding(padding: const EdgeInsets.all(14), child: Text(s.banner!, style: TextStyle(color: p.label, fontWeight: FontWeight.w600))),
              ),
            ),
        ]),
        bottomNavigationBar: GlassNavBar(
          index: tab,
          onTap: s.setTab,
          items: s.isAdmin
              ? const [(CupertinoIcons.person_3_fill, 'Usuarios'), (CupertinoIcons.person_crop_circle_fill, 'Perfil')]
              : const [
                  (CupertinoIcons.shield_fill, 'Inicio'),
                  (CupertinoIcons.heart_fill, 'Salud'),
                  (CupertinoIcons.timer, 'Seguridad'),
                  (CupertinoIcons.person_2_fill, 'Contactos'),
                  (CupertinoIcons.person_crop_circle_fill, 'Perfil'),
                ],
        ),
      ),
      const TakeoverHost(),
    ]);
  }
}
