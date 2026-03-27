import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/firebase_bootstrap.dart';
import 'core/utils/session_timeout.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/orders/data/order_repository.dart';
import 'features/route/data/route_repository.dart';
import 'routing/app_router.dart';
import 'shared/providers/auth_provider.dart';
import 'shared/providers/delivery_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await FirebaseBootstrap.init();
  if (Platform.isAndroid) {
    await FlutterWindowManagerPlus.addFlags(
      FlutterWindowManagerPlus.FLAG_SECURE,
    );
  }

  final authRepo = AuthRepository();
  final authProvider = AuthProvider(authRepo);
  await authProvider.restoreSession();

  runApp(MyApp(authProvider: authProvider));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final SessionTimeoutService _sessionTimeoutService;

  @override
  void initState() {
    super.initState();
    _sessionTimeoutService = SessionTimeoutService(
      timeout: Duration(minutes: AppConstants.sessionTimeoutMinutes),
      onTimeout: () {
        widget.authProvider.logout();
      },
    )..start();
  }

  @override
  void dispose() {
    _sessionTimeoutService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: widget.authProvider),
        Provider<RouteRepository>(create: (_) => RouteRepository()),
        Provider<OrderRepository>(create: (_) => OrderRepository()),
        ChangeNotifierProxyProvider2<
          RouteRepository,
          OrderRepository,
          DeliveryProvider
        >(
          create: (context) => DeliveryProvider(
            context.read<RouteRepository>(),
            context.read<OrderRepository>(),
          ),
          update: (context, routeRepo, orderRepo, old) =>
              old ?? DeliveryProvider(routeRepo, orderRepo),
        ),
      ],
      child: Listener(
        onPointerDown: (_) => _sessionTimeoutService.ping(),
        behavior: HitTestBehavior.translucent,
        child: Consumer<AuthProvider>(
          builder: (context, auth, child) => SafeArea(
            bottom: true,
            top: false,
            left: false,
            right: false,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Fresh Mandi Delivery',
              theme: AppTheme.light(),
              home: AppRouter(isAuthenticated: auth.user != null),
            ),
          ),
        ),
      ),
    );
  }
}
