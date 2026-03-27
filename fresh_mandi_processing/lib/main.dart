import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const ProcessingApp());
}

class ProcessingApp extends StatelessWidget {
  const ProcessingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => ApiService()),
        ChangeNotifierProvider(create: (c) => AuthState(c.read<ApiService>())),
        ChangeNotifierProvider(
          create: (c) => ProcessingState(c.read<ApiService>()),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Fresh Mandi Processing',
        builder: (context, child) => SafeArea(
          bottom: true,
          top: false,
          left: false,
          right: false,
          child: child ?? const SizedBox.shrink(),
        ),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF17834C)),
          scaffoldBackgroundColor: const Color(0xFFF3F6F4),
          textTheme: GoogleFonts.poppinsTextTheme(),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            backgroundColor: Color(0xFFF3F6F4),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF17834C),
                width: 1.6,
              ),
            ),
          ),
          cardTheme: const CardThemeData(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: Colors.white,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthState>().restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (auth.restoring) {
      return const _LoadingScaffold(label: 'Checking session...');
    }
    return auth.token == null ? const LoginScreen() : const RoutesScreen();
  }
}

class ApiService {
  ApiService()
    : _dio = Dio(
        BaseOptions(
          baseUrl:
              dotenv.env['API_BASE_URL'] ??
              'https://backend-rho-one-36.vercel.app/api/v1',
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Content-Type': 'application/json'},
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'token');
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          log('[PROCESSING][REQUEST] ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (res, handler) {
          log(
            '[PROCESSING][RESPONSE] ${res.statusCode} ${res.requestOptions.uri}',
          );
          handler.next(res);
        },
        onError: (e, handler) {
          final friendly = mapError(e);
          log('[PROCESSING][ERROR] ${e.requestOptions.uri} $friendly');
          handler.next(e.copyWith(message: friendly));
        },
      ),
    );
  }

  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String mapError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map &&
          data['message'] is String &&
          (data['message'] as String).trim().isNotEmpty) {
        final backendMessage = (data['message'] as String).trim();
        final lower = backendMessage.toLowerCase();
        if (lower.contains('dioexception') ||
            lower.contains('stack trace') ||
            lower.contains('requestoptions.validatestatus') ||
            lower.contains('client error')) {
          return 'Request failed. Please retry.';
        }
        return backendMessage;
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Server is taking too long to respond. Please retry.';
      }
      if (e.type == DioExceptionType.connectionError) {
        return 'Unable to connect. Check internet and retry.';
      }
      return 'Request failed. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> saveToken(String token) =>
      _storage.write(key: 'token', value: token);
  Future<String?> readToken() => _storage.read(key: 'token');
  Future<void> clearToken() => _storage.delete(key: 'token');

  Future<void> requestOtp(String phone, String deviceId) async {
    await _dio.post(
      '/processing/login',
      data: {'phone': phone, 'device_id': deviceId},
    );
  }

  Future<Map<String, dynamic>> verifyOtp(
    String phone,
    String otp,
    String deviceId,
  ) async {
    final res = await _dio.post(
      '/processing/verify-otp',
      data: {'phone': phone, 'otp': otp, 'device_id': deviceId},
    );
    return (res.data['data'] ?? {}) as Map<String, dynamic>;
  }

  Future<void> generateRoutes() async {
    await _dio.post('/processing/generate-routes');
  }

  Future<List<Map<String, dynamic>>> routesToday() async {
    final res = await _dio.get('/processing/routes-today');
    return ((res.data['data'] ?? []) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> routeOrders(int routeId) async {
    final res = await _dio.get('/processing/route-orders/$routeId');
    return ((res.data['data'] ?? []) as List).cast<Map<String, dynamic>>();
  }

  Future<void> lockOrder(int orderId) async {
    await _dio.post('/processing/lock-order', data: {'order_id': orderId});
  }

  Future<void> unlockOrder(int orderId) async {
    await _dio.post('/processing/unlock-order', data: {'order_id': orderId});
  }

  Future<void> scanPack(
    int orderId,
    String barcode,
    String? crateNumber,
  ) async {
    await _dio.post(
      '/processing/scan-pack',
      data: {
        'order_id': orderId,
        'barcode': barcode,
        if (crateNumber != null && crateNumber.trim().isNotEmpty)
          'crate_number': crateNumber.trim(),
      },
    );
  }

  Future<void> printRouteLabels(int routeId) async {
    await _dio.post(
      '/processing/print-route-labels',
      data: {'route_id': routeId},
    );
  }
}

class AuthState extends ChangeNotifier {
  AuthState(this._api);
  final ApiService _api;

  String? token;
  bool restoring = true;
  bool loading = false;
  String? error;
  String? pendingPhone;

  Future<void> restore() async {
    token = await _api.readToken();
    restoring = false;
    notifyListeners();
  }

  Future<bool> requestOtp(String phone) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final normalized = _normalizePhone(phone);
      if (normalized == null) {
        error = 'Enter valid Indian mobile number.';
        return false;
      }
      pendingPhone = normalized;
      await _api.requestOtp(normalized, 'processing-device-001');
      return true;
    } catch (e) {
      error = _api.mapError(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String otp) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (pendingPhone == null) {
        error = 'Request OTP first.';
        return false;
      }
      if (otp.trim().length != 6) {
        error = 'Enter 6-digit OTP.';
        return false;
      }
      final data = await _api.verifyOtp(
        pendingPhone!,
        otp.trim(),
        'processing-device-001',
      );
      final t = (data['token'] ?? '').toString();
      if (t.isEmpty) {
        error = 'Login failed. Please retry.';
        return false;
      }
      await _api.saveToken(t);
      token = t;
      return true;
    } catch (e) {
      error = _api.mapError(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    token = null;
    pendingPhone = null;
    notifyListeners();
  }

  String? _normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '+91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
    if (digits.length == 13 && digits.startsWith('091')) {
      return '+91${digits.substring(3)}';
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+91${digits.substring(1)}';
    }
    return null;
  }
}

class ProcessingState extends ChangeNotifier {
  ProcessingState(this._api);
  final ApiService _api;

  bool loadingRoutes = false;
  bool loadingOrders = false;
  String? error;
  List<Map<String, dynamic>> routes = const [];
  List<Map<String, dynamic>> orders = const [];

  Future<void> loadRoutes({bool regenerate = false}) async {
    loadingRoutes = true;
    error = null;
    notifyListeners();
    try {
      if (regenerate) await _api.generateRoutes();
      routes = await _api.routesToday();
    } catch (e) {
      error = _api.mapError(e);
    } finally {
      loadingRoutes = false;
      notifyListeners();
    }
  }

  Future<void> loadRouteOrders(int routeId) async {
    loadingOrders = true;
    error = null;
    notifyListeners();
    try {
      orders = await _api.routeOrders(routeId);
    } catch (e) {
      error = _api.mapError(e);
    } finally {
      loadingOrders = false;
      notifyListeners();
    }
  }

  Future<String?> lockOrder(int orderId) async {
    try {
      await _api.lockOrder(orderId);
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }

  Future<String?> unlockOrder(int orderId) async {
    try {
      await _api.unlockOrder(orderId);
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }

  Future<String?> scanPack(int orderId, String barcode, String? crate) async {
    try {
      await _api.scanPack(orderId, barcode, crate);
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }

  Future<String?> printRouteLabels(int routeId) async {
    try {
      await _api.printRouteLabels(routeId);
      return null;
    } catch (e) {
      return _api.mapError(e);
    }
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final phoneDigits = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final canSubmit = phoneDigits.length == 10 && !auth.loading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const _AuthTopBanner(),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Login to continue',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Use your admin-created processing account. No customer or delivery login works here.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Mobile Number',
                              prefixText: '+91 ',
                              counterText: '',
                              hintText: '9876543210',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: canSubmit
                                  ? () async {
                                      FocusScope.of(context).unfocus();
                                      final ok = await auth.requestOtp(
                                        _phoneCtrl.text,
                                      );
                                      if (!context.mounted) return;
                                      if (ok) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const OtpScreen(),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                              child: auth.loading
                                  ? const _BtnLoader()
                                  : const Text('Send OTP'),
                            ),
                          ),
                          if ((auth.error ?? '').isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _ErrorBox(text: auth.error!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  int _seconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    _focusNodes = List.generate(6, (_) => FocusNode());
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_seconds == 0) {
        t.cancel();
        return;
      }
      setState(() => _seconds -= 1);
    });
  }

  String _otp() => _controllers.map((e) => e.text).join();

  void _onOtpChanged(int index, String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length > 1) {
      for (var i = 0; i < 6; i++) {
        _controllers[i].text = i < digitsOnly.length ? digitsOnly[i] : '';
      }
      _focusNodes[(digitsOnly.length.clamp(1, 6)) - 1].requestFocus();
      return;
    }

    if (digitsOnly.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (digitsOnly.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final canResend = _seconds == 0 && !auth.loading;
    final canVerify = _otp().length == 6 && !auth.loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter 6-digit OTP',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sent to ${auth.pendingPhone ?? ''}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          return SizedBox(
                            width: 48,
                            child: TextField(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              keyboardType: TextInputType.number,
                              textInputAction: index == 5
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: const InputDecoration(
                                counterText: '',
                              ),
                              onChanged: (v) {
                                _onOtpChanged(index, v);
                                setState(() {});
                              },
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: canResend
                              ? () async {
                                  final ok = await auth.requestOtp(
                                    auth.pendingPhone ?? '',
                                  );
                                  if (!mounted) return;
                                  if (ok) {
                                    for (final c in _controllers) {
                                      c.clear();
                                    }
                                    _focusNodes.first.requestFocus();
                                    setState(_startTimer);
                                  }
                                }
                              : null,
                          child: Text(
                            canResend ? 'Resend OTP' : 'Resend in ${_seconds}s',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: canVerify
                              ? () async {
                                  FocusScope.of(context).unfocus();
                                  final ok = await auth.verifyOtp(_otp());
                                  if (!context.mounted) return;
                                  if (ok) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const RoutesScreen(),
                                      ),
                                      (_) => false,
                                    );
                                  }
                                }
                              : null,
                          child: auth.loading
                              ? const _BtnLoader()
                              : const Text('Verify & Continue'),
                        ),
                      ),
                      if ((auth.error ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ErrorBox(text: auth.error!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoutesScreen extends StatefulWidget {
  const RoutesScreen({super.key});

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProcessingState>().loadRoutes(regenerate: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProcessingState>();
    final auth = context.read<AuthState>();

    final routes = state.routes;
    final totalRoutes = routes.length;
    final packedRoutes = routes
        .where((e) => (e['pending_orders'] as num?)?.toInt() == 0)
        .length;
    final pendingRoutes = totalRoutes - packedRoutes;
    final groupedRoutes = <String, List<Map<String, dynamic>>>{};
    for (final r in routes) {
      final sectorName =
          '${r['sector_name'] ?? r['sector_code'] ?? 'Unassigned Sector'}';
      groupedRoutes.putIfAbsent(sectorName, () => []).add(r);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing Dashboard'),
        actions: [
          IconButton(
            onPressed: state.loadingRoutes
                ? null
                : () => state.loadRoutes(regenerate: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () async {
              await auth.logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => state.loadRoutes(regenerate: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.hub, color: Color(0xFF17834C)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Routes are auto-generated after order cutoff. No manual sorting or filters.',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _KpiGrid(
              items: [
                _KpiItem('Total Routes', '$totalRoutes'),
                _KpiItem('Routes Packed', '$packedRoutes'),
                _KpiItem('Routes Pending', '$pendingRoutes'),
              ],
            ),
            const SizedBox(height: 12),
            if (state.loadingRoutes)
              const _LoadingBody(label: 'Generating routes...'),
            if ((state.error ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ErrorBox(text: state.error!),
              ),
            if (!state.loadingRoutes && routes.isEmpty)
              const _EmptyBox(
                title: 'No Routes Available',
                subtitle: 'No orders are available for processing right now.',
              ),
            for (final entry in groupedRoutes.entries) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  entry.key,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              ...entry.value.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RouteTile(
                    route: r,
                    onOpen: () {
                      final routeId = (r['route_id'] as num).toInt();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RouteOrdersScreen(
                            routeId: routeId,
                            routeCode: '${r['route_code']}',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
          ],
        ),
      ),
    );
  }
}

class RouteOrdersScreen extends StatefulWidget {
  const RouteOrdersScreen({
    super.key,
    required this.routeId,
    required this.routeCode,
  });
  final int routeId;
  final String routeCode;

  @override
  State<RouteOrdersScreen> createState() => _RouteOrdersScreenState();
}

class _RouteOrdersScreenState extends State<RouteOrdersScreen> {
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProcessingState>().loadRouteOrders(widget.routeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProcessingState>();
    final orders = state.orders;
    final summary = <String, num>{};

    for (final o in orders) {
      for (final i in (o['items'] as List? ?? const [])) {
        final name = '${(i as Map)['name'] ?? '-'}';
        final qty = (i['quantity'] as num?) ?? 0;
        summary[name] = (summary[name] ?? 0) + qty;
      }
    }

    final groupedByBuilding = <String, List<Map<String, dynamic>>>{};
    for (final o in orders) {
      final building = '${o['building_name'] ?? 'Building'}';
      groupedByBuilding.putIfAbsent(building, () => []).add(o);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Route ${widget.routeCode}'),
        actions: [
          IconButton(
            onPressed: _printing
                ? null
                : () async {
                    setState(() => _printing = true);
                    final err = await context
                        .read<ProcessingState>()
                        .printRouteLabels(widget.routeId);
                    if (!context.mounted) return;
                    setState(() => _printing = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(err ?? 'Route labels marked printed.'),
                      ),
                    );
                  },
            icon: _printing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print),
          ),
        ],
      ),
      body: state.loadingOrders
          ? const _LoadingBody(label: 'Loading route orders...')
          : RefreshIndicator(
              onRefresh: () => state.loadRouteOrders(widget.routeId),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: _miniStat(
                              'Orders',
                              '${orders.length}',
                              const Color(0xFF475467),
                            ),
                          ),
                          Expanded(
                            child: _miniStat(
                              'Packed',
                              '${orders.where((e) => '${e['packing_status']}'.toLowerCase() == 'packed').length}',
                              const Color(0xFF15803D),
                            ),
                          ),
                          Expanded(
                            child: _miniStat(
                              'Pending',
                              '${orders.where((e) => '${e['packing_status']}'.toLowerCase() != 'packed').length}',
                              const Color(0xFFB54708),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Route Item Summary',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if (summary.isEmpty)
                            const Text('No item summary available')
                          else
                            ...summary.entries.map(
                              (e) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('${e.key} - ${e.value}'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if ((state.error ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ErrorBox(text: state.error!),
                    ),
                  if (orders.isEmpty)
                    const _EmptyBox(
                      title: 'No Orders',
                      subtitle: 'This route does not have orders for today.',
                    ),
                  for (final entry in groupedByBuilding.entries) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...entry.value.map(
                      (o) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stop ${o['stop_number'] ?? '-'} • ${o['customer_name']}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Floor ${o['floor_number'] ?? 0} • Flat ${o['flat_number'] ?? '-'}',
                                  style: const TextStyle(color: Colors.black87),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${o['packing_status']} • ${o['print_status']}',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    _smallStatusChip('${o['packing_status']}'),
                                    const Spacer(),
                                    FilledButton.tonal(
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PackOrderScreen(
                                              order: o,
                                              routeId: widget.routeId,
                                            ),
                                          ),
                                        );
                                        if (!context.mounted) return;
                                        await context
                                            .read<ProcessingState>()
                                            .loadRouteOrders(widget.routeId);
                                      },
                                      child: Text(
                                        '${o['packing_status']}'
                                                    .toLowerCase() ==
                                                'packed'
                                            ? 'View'
                                            : 'Pack',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class PackOrderScreen extends StatefulWidget {
  const PackOrderScreen({
    super.key,
    required this.order,
    required this.routeId,
  });

  final Map<String, dynamic> order;
  final int routeId;

  @override
  State<PackOrderScreen> createState() => _PackOrderScreenState();
}

class _PackOrderScreenState extends State<PackOrderScreen> {
  bool _locking = false;
  bool _packing = false;
  final _crateCtrl = TextEditingController();
  final Set<int> _checkedIndices = {};
  late final ProcessingState _processingState;

  bool get _isPacked =>
      '${widget.order['packing_status']}'.toLowerCase().trim() == 'packed';

  @override
  void initState() {
    super.initState();
    _processingState = context.read<ProcessingState>();
    _crateCtrl.text = '${widget.order['crate_suggestion'] ?? ''}';
    final items = (widget.order['items'] as List? ?? const []);
    for (var i = 0; i < items.length; i++) {
      _checkedIndices.add(i);
    }
    if (!_isPacked) {
      _lock();
    }
  }

  @override
  void dispose() {
    if (!_isPacked) {
      _processingState.unlockOrder((widget.order['order_id'] as num).toInt());
    }
    _crateCtrl.dispose();
    super.dispose();
  }

  Future<void> _lock() async {
    setState(() => _locking = true);
    final msg = await _processingState.lockOrder(
      (widget.order['order_id'] as num).toInt(),
    );
    if (!mounted) return;
    setState(() => _locking = false);
    if (msg != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  Future<void> _scanAndPack() async {
    final items = (widget.order['items'] as List? ?? const []);
    if (_checkedIndices.length != items.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete item checklist before packing.'),
        ),
      );
      return;
    }

    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanScreen()),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;

    setState(() => _packing = true);
    final msg = await _processingState.scanPack(
      (widget.order['order_id'] as num).toInt(),
      scanned,
      _crateCtrl.text,
    );

    if (!mounted) return;
    setState(() => _packing = false);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg ?? 'Packed successfully.')));

    if (msg == null) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.order['items'] as List? ?? const []);
    return Scaffold(
      appBar: AppBar(title: Text('Order #${widget.order['order_id']}')),
      body: _locking
          ? const _LoadingBody(label: 'Locking order...')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.order['customer_name']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${widget.order['address']}'),
                        const SizedBox(height: 6),
                        Text(
                          'Suggested Crate: ${widget.order['crate_suggestion'] ?? '-'}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _PackingProgress(
                      scanDone: _isPacked,
                      itemsDone: _checkedIndices.length == items.length,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Item Checklist',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (items.isEmpty)
                          const Text('No items available')
                        else
                          ...items.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final i = entry.value as Map;
                            return CheckboxListTile(
                              value: _checkedIndices.contains(idx),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _checkedIndices.add(idx);
                                  } else {
                                    _checkedIndices.remove(idx);
                                  }
                                });
                              },
                              title: Text('${i['name']}'),
                              subtitle: Text('Qty: ${i['quantity']}'),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isPacked)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.verified, color: Color(0xFF15803D)),
                          SizedBox(width: 8),
                          Text(
                            'This order is already packed.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  TextField(
                    controller: _crateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Crate Number',
                      hintText: 'CRATE-A',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _packing ? null : _scanAndPack,
                      icon: _packing
                          ? const _BtnLoader()
                          : const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan Barcode & Mark Packed'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Barcode'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Enter exact barcode'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    if (!mounted || value == null || value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Order Barcode'),
        actions: [
          IconButton(onPressed: _manualEntry, icon: const Icon(Icons.keyboard)),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (context, error) {
              return _ScanFallback(
                message:
                    'Camera is not available right now. You can still enter barcode manually.',
                onManual: _manualEntry,
              );
            },
            onDetect: (capture) {
              if (capture.barcodes.isEmpty) return;
              final value = capture.barcodes.first.rawValue;
              if (value == null || value.isEmpty) return;
              Navigator.pop(context, value);
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _manualEntry,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter Barcode Manually'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFallback extends StatelessWidget {
  const _ScanFallback({required this.message, required this.onManual});

  final String message;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 32,
                  color: Colors.black54,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onManual,
                    child: const Text('Enter Barcode'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.title,
    required this.subtitle,
    this.light = false,
  });

  final String title;
  final String subtitle;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: light ? Colors.white24 : const Color(0xFFE7F6EE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.local_shipping,
            color: light ? Colors.white : const Color(0xFF17834C),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: light ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: light ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthTopBanner extends StatelessWidget {
  const _AuthTopBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17834C), Color(0xFF0E6237)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrandHeader(
            title: 'Fresh Mandi Processing',
            subtitle: 'Smart route-based warehouse operations',
            light: true,
          ),
          SizedBox(height: 10),
          Text(
            'Auto-grouped by Sector → Building → Route',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 2),
          Text(
            'No manual sorting. Fast scan-based packing.',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD5D5)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFFB42318))),
    );
  }
}

class _KpiItem {
  _KpiItem(this.label, this.value);
  final String label;
  final String value;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});
  final List<_KpiItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 700 ? 3 : 2;
        final aspect = constraints.maxWidth >= 700 ? 1.6 : 1.8;
        return GridView.builder(
          itemCount: items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: aspect,
          ),
          itemBuilder: (context, i) {
            final item = items[i];
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      item.value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PackingProgress extends StatelessWidget {
  const _PackingProgress({required this.itemsDone, required this.scanDone});

  final bool itemsDone;
  final bool scanDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Packing Steps',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _stepRow('1. Verify item checklist', itemsDone),
        const SizedBox(height: 6),
        _stepRow('2. Scan barcode / QR', scanDone),
      ],
    );
  }

  Widget _stepRow(String label, bool done) {
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: done ? const Color(0xFF15803D) : const Color(0xFF98A2B3),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: done ? const Color(0xFF15803D) : const Color(0xFF344054),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

Widget _smallStatusChip(String status) {
  final normalized = status.toLowerCase();
  final (bg, fg) = switch (normalized) {
    'packed' => (const Color(0xFFE9F8EF), const Color(0xFF15803D)),
    'printed' => (const Color(0xFFFFF2E5), const Color(0xFFB54708)),
    _ => (const Color(0xFFF2F4F7), const Color(0xFF475467)),
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      status.toUpperCase(),
      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11),
    ),
  );
}

Widget _miniStat(String label, String value, Color color) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ],
  );
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.route, required this.onOpen});

  final Map<String, dynamic> route;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final total = (route['total_orders'] as num?)?.toInt() ?? 0;
    final packed = (route['packed_orders'] as num?)?.toInt() ?? 0;
    final pending = (route['pending_orders'] as num?)?.toInt() ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sector ${route['sector_code']} - ${route['route_code']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip(
                  'Total: $total',
                  const Color(0xFF475467),
                  const Color(0xFFF2F4F7),
                ),
                _statusChip(
                  'Packed: $packed',
                  const Color(0xFF15803D),
                  const Color(0xFFE9F8EF),
                ),
                _statusChip(
                  'Pending: $pending',
                  const Color(0xFFB54708),
                  const Color(0xFFFFF2E5),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onOpen,
                child: const Text('Open Route'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.inbox, size: 34, color: Colors.black45),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _LoadingBody(label: label));
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 10),
          Text(label),
        ],
      ),
    );
  }
}

class _BtnLoader extends StatelessWidget {
  const _BtnLoader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}
