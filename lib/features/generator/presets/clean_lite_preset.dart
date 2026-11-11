import 'dart:io';
import 'package:path/path.dart' as p;
import '../../wizard/models/project_config.dart';

class CleanLitePreset {
  CleanLitePreset._();

  static File _resolveFile(String targetPath, String relativePath) {
    return File(p.normalize(p.join(targetPath.isEmpty ? '.' : targetPath, relativePath)));
  }

  static Future<void> _writeFile(File file, String content) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    } on FileSystemException catch (e) {
      throw FileSystemException(
        'Failed to write scaffolded preset file "${file.path}": ${e.message}',
        file.path,
        e.osError,
      );
    }
  }

  static Future<void> synthesize(String targetPath, ProjectConfig config) async {
    await _writeTheme(targetPath, config);
    await _writeErrors(targetPath);
    await _writeNetwork(targetPath);
    await _writeAuthFeature(targetPath);
    await _writeDi(targetPath);
    await _writeScreens(targetPath, config);
    await _writeRouter(targetPath, config);
    await _writeMain(targetPath, config);
  }

  static Future<void> _writeTheme(String targetPath, ProjectConfig config) async {
    final file = _resolveFile(targetPath, 'lib/core/theme/app_theme.dart');
    final seedHex = config.seedColor.value.toRadixString(16).padLeft(8, '0');

    await _writeFile(file, '''
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  static const Color seedColor = Color(0x$seedHex);

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
''');
  }

  static Future<void> _writeErrors(String targetPath) async {
    final file = _resolveFile(targetPath, 'lib/core/errors/failures.dart');

    await _writeFile(file, '''
/// Idiomatic Dart 3 sealed class hierarchy for enterprise-grade error handling.
sealed class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure([super.message = 'Internal server error occurred.', this.statusCode]);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No active internet connection.']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Invalid authentication credentials.']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Local cache retrieval failed.']);
}
''');
  }

  static Future<void> _writeNetwork(String targetPath) async {
    final file = _resolveFile(targetPath, 'lib/core/network/dio_client.dart');

    await _writeFile(file, '''
import 'package:dio/dio.dart';
import '../errors/failures.dart';

/// Pre-configured Dio client with interceptors and robust error wrapping.
class DioClient {
  late final Dio dio;

  DioClient({String baseUrl = 'https://api.example.com'}) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Add JWT Bearer token here if available
          return handler.next(options);
        },
        onError: (DioException e, handler) {
          // Centralized network logging
          return handler.next(e);
        },
      ),
    );
  }

  Failure handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) {
          return const AuthFailure();
        }
        return ServerFailure(error.response?.data?['message'] ?? 'Server error', status);
      default:
        return ServerFailure(error.message ?? 'Unknown request failure');
    }
  }
}
''');
  }

  static Future<void> _writeAuthFeature(String targetPath) async {
    // 1. Model
    final modelFile = _resolveFile(targetPath, 'lib/features/auth/data/models/user_model.dart');
    await _writeFile(modelFile, '''
class UserModel {
  final String id;
  final String email;
  final String name;

  const UserModel({required this.id, required this.email, required this.name});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};
}
''');

    // 2. Repository
    final repoFile = _resolveFile(targetPath, 'lib/features/auth/data/repositories/auth_repository.dart');
    await _writeFile(repoFile, '''
import '../../../../core/network/dio_client.dart';
import '../models/user_model.dart';

abstract class AuthRepository {
  Future<UserModel> login(String email, String password);
  Future<void> logout();
  Future<UserModel?> getCachedUser();
}

class AuthRepositoryImpl implements AuthRepository {
  final DioClient client;
  UserModel? _currentUser;

  AuthRepositoryImpl({required this.client});

  @override
  Future<UserModel> login(String email, String password) async {
    // Simulating Dio API request:
    // final response = await client.dio.post('/auth/login', data: {'email': email, 'password': password});
    await Future.delayed(const Duration(milliseconds: 600));

    if (password.length >= 6) {
      _currentUser = UserModel(
        id: 'usr_\${email.hashCode}',
        email: email,
        name: email.split('@').first,
      );
      return _currentUser!;
    } else {
      throw Exception('Invalid password. Minimum 6 characters.');
    }
  }

  @override
  Future<void> logout() async {
    _currentUser = null;
  }

  @override
  Future<UserModel?> getCachedUser() async {
    return _currentUser;
  }
}
''');

    // 3. BLoC (Event, State, Bloc)
    final eventFile = _resolveFile(targetPath, 'lib/features/auth/bloc/auth_event.dart');
    await _writeFile(eventFile, '''
import 'package:flutter/foundation.dart';

@immutable
sealed class AuthEvent {}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginSubmitted extends AuthEvent {
  final String email;
  final String password;
  AuthLoginSubmitted({required this.email, required this.password});
}

class AuthLogoutRequested extends AuthEvent {}
''');

    final stateFile = _resolveFile(targetPath, 'lib/features/auth/bloc/auth_state.dart');
    await _writeFile(stateFile, '''
import 'package:flutter/foundation.dart';
import '../data/models/user_model.dart';

@immutable
sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);
}

class AuthUnauthenticated extends AuthState {}

class AuthFailureState extends AuthState {
  final String errorMessage;
  const AuthFailureState(this.errorMessage);
}
''');

    final blocFile = _resolveFile(targetPath, 'lib/features/auth/bloc/auth_bloc.dart');
    await _writeFile(blocFile, '''
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository repository;

  AuthBloc({required this.repository}) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginSubmitted>(_onLoginSubmitted);
    on<AuthLogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onCheckRequested(AuthCheckRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    await Future.delayed(const Duration(milliseconds: 700));
    final cached = await repository.getCachedUser();
    if (cached != null) {
      emit(AuthAuthenticated(cached));
    } else {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLoginSubmitted(AuthLoginSubmitted event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await repository.login(event.email, event.password);
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthFailureState(e.toString().replaceAll('Exception: ', '')));
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLogoutRequested(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    await repository.logout();
    emit(AuthUnauthenticated());
  }
}
''');
  }

  static Future<void> _writeDi(String targetPath) async {
    final file = _resolveFile(targetPath, 'lib/core/di/injection.dart');

    await _writeFile(file, '''
import 'package:get_it/get_it.dart';
import '../network/dio_client.dart';
import '../../features/auth/data/repositories/auth_repository.dart';
import '../../features/auth/bloc/auth_bloc.dart';

final getIt = GetIt.instance;

/// Global dependency injection registration.
Future<void> setupLocator() async {
  // 1. Core Network
  getIt.registerLazySingleton<DioClient>(() => DioClient());

  // 2. Repositories
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(client: getIt<DioClient>()),
  );

  // 3. BLoCs / Cubits
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(repository: getIt<AuthRepository>()),
  );
}
''');
  }

  static Future<void> _writeScreens(String targetPath, ProjectConfig config) async {
    // 1. Splash Screen
    final splashFile = _resolveFile(targetPath, 'lib/features/splash/presentation/splash_screen.dart');
    await _writeFile(splashFile, '''
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.layers_rounded, size: 48, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              '${config.projectName}',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ],
        ),
      ),
    );
  }
}
''');

    // 2. Login Page with BlocConsumer
    final loginFile = _resolveFile(targetPath, 'lib/features/auth/presentation/login_page.dart');
    await _writeFile(loginFile, '''
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController(text: 'dev@enterprise.com');
  final _passwordController = TextEditingController(text: 'secret123');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<AuthBloc>().add(
            AuthLoginSubmitted(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthFailureState) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage), backgroundColor: theme.colorScheme.error),
            );
          }
          if (state is AuthAuthenticated) {
            context.go('/home');
          }
        },
        builder: (context, state) {
          final isLoading = state is AuthLoading;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.shield_rounded, size: 36, color: theme.colorScheme.primary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Clean-Lite Architecture',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Powered by BLoC 8.x + Dio + GetIt',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),

                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Corporate Email', border: OutlineInputBorder()),
                        validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                      ),
                      const SizedBox(height: 24),

                      ElevatedButton(
                        onPressed: isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign In via BLoC', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
''');

    // 3. Shell Screen (Tabs, Drawer, or AdaptiveRail)
    final shellFile = _resolveFile(targetPath, 'lib/features/home/presentation/shell_screen.dart');
    await _writeFile(shellFile, _generateShellCode(config));

    // 4. Home Page
    final homeFile = _resolveFile(targetPath, 'lib/features/home/presentation/home_page.dart');
    await _writeFile(homeFile, '''
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          context.go('/login');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Clean-Lite Dashboard'),
          actions: [
            IconButton(
              tooltip: 'Sign Out via BLoC',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  final user = state is AuthAuthenticated ? state.user : null;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: const Icon(Icons.layers_rounded, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome, \${user?.name ?? "Developer"}!',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.email ?? '',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Enterprise-Ready Architecture 🏛️',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This preset implements a Feature-First Clean-Lite structure:\\n'
                '• BLoC / Cubit: Predictable state transitions with Dart 3 sealed classes\\n'
                '• DioClient: Centralized timeout, auth headers & network error handling\\n'
                '• GetIt: Fast decoupled dependency injection\\n'
                '• Failures: Type-safe sealed error hierarchy',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''');

    final settingsFile = _resolveFile(targetPath, 'lib/features/home/presentation/settings_page.dart');
    await _writeFile(settingsFile, '''
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.tune_rounded),
            title: Text('API Environment'),
            subtitle: Text('Configured via DioClient BaseOptions'),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
          ),
        ],
      ),
    );
  }
}
''');
  }

  static String _generateShellCode(ProjectConfig config) {
    switch (config.navigationStyle) {
      case NavigationStyle.tabs:
        return '''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
''';

      case NavigationStyle.drawer:
        return '''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: NavigationDrawer(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          Navigator.of(context).pop();
          navigationShell.goBranch(index);
        },
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text('Enterprise Menu', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          NavigationDrawerDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Home')),
          NavigationDrawerDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Settings')),
        ],
      ),
      body: navigationShell,
    );
  }
}
''';

      case NavigationStyle.adaptiveRail:
        return '''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ShellScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: (index) => navigationShell.goBranch(index),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Home')),
                    NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Settings')),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }

        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}
''';
    }
  }

  static Future<void> _writeRouter(String targetPath, ProjectConfig config) async {
    final file = _resolveFile(targetPath, 'lib/core/router/app_router.dart');

    await _writeFile(file, '''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/home/presentation/settings_page.dart';
import '../../features/home/presentation/shell_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ShellScreen(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
''');
  }

  static Future<void> _writeMain(String targetPath, ProjectConfig config) async {
    final file = _resolveFile(targetPath, 'lib/main.dart');

    await _writeFile(file, '''
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Dependency Injection Service Locator
  await setupLocator();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>()..add(AuthCheckRequested()),
        ),
      ],
      child: MaterialApp.router(
        title: '${config.projectName}',
        debugShowCheckedModeBanner: false,
        routerConfig: appRouter,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ${config.enableDarkTheme ? 'ThemeMode.dark' : 'ThemeMode.system'},
      ),
    );
  }
}
''');
  }
}
