import 'dart:io';
import 'package:path/path.dart' as p;
import '../../wizard/models/project_config.dart';

class SaasPreset {
  SaasPreset._();

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
    await _writeAuthModels(targetPath);
    await _writeAuthProvider(targetPath);
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

  static Future<void> _writeAuthModels(String targetPath) async {
    final file = _resolveFile(targetPath, 'lib/features/auth/models/user_model.dart');

    await _writeFile(file, '''
class AppUser {
  final String id;
  final String email;
  final String displayName;
  final String? avatarUrl;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.avatarUrl,
  });

  factory AppUser.mock() {
    return const AppUser(
      id: 'usr_101',
      email: 'founder@flrd.dev',
      displayName: 'Alex Rivers',
    );
  }
}
''');
  }

  static Future<void> _writeAuthProvider(String targetPath) async {
    final file = _resolveFile(targetPath, 'lib/features/auth/providers/auth_provider.dart');

    await _writeFile(file, '''
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final AppUser? user;
  final String? errorMessage;

  const AuthState({
    this.isLoading = true,
    this.isAuthenticated = false,
    this.user,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    AppUser? user,
    String? errorMessage,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// The AuthNotifier extends ChangeNotifier so GoRouter can use it directly
/// as a `refreshListenable`, kicking unauthenticated users out immediately.
class AuthNotifier extends ChangeNotifier {
  AuthState _state = const AuthState();
  AuthState get state => _state;

  AuthNotifier() {
    _initSession();
  }

  Future<void> _initSession() async {
    // Simulating token verification / Supabase session restoration
    await Future.delayed(const Duration(milliseconds: 900));
    _state = _state.copyWith(isLoading: false, isAuthenticated: false);
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));

    // Connect real Supabase / Firebase auth here:
    // final res = await Supabase.instance.client.auth.signInWithPassword(...);
    if (email.isNotEmpty && password.length >= 6) {
      _state = _state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        user: AppUser(id: 'usr_\${email.hashCode}', email: email, displayName: email.split('@').first),
      );
      notifyListeners();
      return true;
    } else {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid credentials. Password must be at least 6 characters.',
      );
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _state = const AuthState(isLoading: false, isAuthenticated: false, user: null);
    notifyListeners();
  }
}

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  return AuthNotifier();
});
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
              child: Icon(Icons.bolt_rounded, size: 48, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              '${config.projectName}',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
''');

    // 2. Login Screen
    final loginFile = _resolveFile(targetPath, 'lib/features/auth/presentation/login_screen.dart');
    await _writeFile(loginFile, '''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController(text: 'demo@flrd.dev');
  final _passwordController = TextEditingController(text: 'secret123');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() ?? false) {
      await ref.read(authNotifierProvider).login(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authNotifierProvider).state;

    return Scaffold(
      body: Center(
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
                      child: Icon(Icons.lock_person_rounded, size: 36, color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to access your ${config.projectName} account',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),

                  if (authState.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        authState.errorMessage!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.key_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: authState.isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () => context.go('/register'),
                    child: const Text("Don't have an account? Sign up"),
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
''');

    // 3. Register Screen
    final registerFile = _resolveFile(targetPath, 'lib/features/auth/presentation/register_screen.dart');
    await _writeFile(registerFile, '''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Register new account'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/login'),
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''');

    // 4. Shell Screen (Implements the Navigation style: Tabs, Drawer, AdaptiveRail)
    final shellFile = _resolveFile(targetPath, 'lib/features/home/presentation/shell_screen.dart');
    await _writeFile(shellFile, _generateShellCode(config));

    // 5. Home, Explore, and Profile Screens
    final homeFile = _resolveFile(targetPath, 'lib/features/home/presentation/home_screen.dart');
    await _writeFile(homeFile, '''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authNotifierProvider).state.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign Out (Tests instant GoRouter kick)',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authNotifierProvider).logout(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        user?.displayName.characters.first.toUpperCase() ?? 'U',
                        style: TextStyle(fontSize: 20, color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, \${user?.displayName ?? "Developer"}! 👋',
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
            ),
            const SizedBox(height: 24),
            Text(
              'FLRD Protected Route Active 🛡️',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Try changing the URL to an unauthenticated route or click the Logout button in the top right to verify that GoRouter redirects instantly without exposing unauthorized views.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
''');

    final exploreFile = _resolveFile(targetPath, 'lib/features/home/presentation/explore_screen.dart');
    await _writeFile(exploreFile, '''
import 'package:flutter/material.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: const Center(
        child: Text('Explore Section - Ready for features!'),
      ),
    );
  }
}
''');

    final profileFile = _resolveFile(targetPath, 'lib/features/home/presentation/profile_screen.dart');
    await _writeFile(profileFile, '''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Account Details'),
            subtitle: const Text('Manage your credentials'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () => ref.read(authNotifierProvider).logout(),
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
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
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
            child: Text('Navigation', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          NavigationDrawerDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Home')),
          NavigationDrawerDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: Text('Explore')),
          NavigationDrawerDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Text('Profile')),
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
                    NavigationRailDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: Text('Explore')),
                    NavigationRailDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Text('Profile')),
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
              NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/home/presentation/explore_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/profile_screen.dart';
import '../../features/home/presentation/shell_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authNotifierProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    // 🛡️ REFRESH LISTEN_ABLE: Forces instant re-evaluation whenever auth state mutates!
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final authState = authNotifier.state;
      final isSplash = state.matchedLocation == '/splash';
      final isLoggingIn = state.matchedLocation == '/login';
      final isRegistering = state.matchedLocation == '/register';

      // 1. While initial splash session verification is running, remain on splash
      if (authState.isLoading) {
        return '/splash';
      }

      // If finished loading and still on splash, redirect to appropriate route
      if (isSplash) {
        return authState.isAuthenticated ? '/home' : '/login';
      }

      // 2. HARD SECURITY GUARD:
      // If user is unauthenticated and tries to hit ANY route other than login/register,
      // kick them immediately back to /login. Bypassing via URL change is impossible.
      if (!authState.isAuthenticated) {
        if (!isLoggingIn && !isRegistering) {
          return '/login';
        }
        return null;
      }

      // 3. User is already authenticated:
      // Prevent access to login/register, push directly to dashboard.
      if (isLoggingIn || isRegistering) {
        return '/home';
      }

      // Route access permitted
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // 🚀 Authenticated Shell Branch (StatefulNavigationShell keeps tab states preserved)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ShellScreen(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
''');
  }

  static Future<void> _writeMain(String targetPath, ProjectConfig config) async {
    final file = _resolveFile(targetPath, 'lib/main.dart');

    await _writeFile(file, '''
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: AppRoot(),
    ),
  );
}

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: '${config.projectName}',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ${config.enableDarkTheme ? 'ThemeMode.dark' : 'ThemeMode.system'},
    );
  }
}
''');
  }
}
