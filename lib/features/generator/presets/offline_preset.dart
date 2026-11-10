import 'dart:io';
import '../../wizard/models/project_config.dart';

class OfflinePreset {
  OfflinePreset._();

  static Future<void> synthesize(String targetPath, ProjectConfig config) async {
    await _writeTheme(targetPath, config);
    await _writeDatabaseHelper(targetPath);
    await _writeItemFeature(targetPath);
    await _writeSettingsFeature(targetPath);
    await _writeScreens(targetPath, config);
    await _writeRouter(targetPath, config);
    await _writeMain(targetPath, config);
  }

  static Future<void> _writeTheme(String targetPath, ProjectConfig config) async {
    final file = File('$targetPath/lib/core/theme/app_theme.dart');
    await file.parent.create(recursive: true);

    final seedHex = config.seedColor.value.toRadixString(16).padLeft(8, '0');

    await file.writeAsString('''
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

  static Future<void> _writeDatabaseHelper(String targetPath) async {
    final file = File('$targetPath/lib/core/database/database_helper.dart');
    await file.parent.create(recursive: true);

    await file.writeAsString('''
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../features/items/models/item_model.dart';

/// Robust local SQLite database manager.
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_local_data.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute(\'''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        isCompleted INTEGER NOT NULL,
        createdAt TEXT NOT NULL
      )
    \''');
  }

  Future<ItemModel> createItem(ItemModel item) async {
    final db = await instance.database;
    final id = await db.insert('items', item.toMap());
    return item.copyWith(id: id);
  }

  Future<List<ItemModel>> getAllItems() async {
    final db = await instance.database;
    final result = await db.query('items', orderBy: 'id DESC');
    return result.map((json) => ItemModel.fromMap(json)).toList();
  }

  Future<int> updateItem(ItemModel item) async {
    final db = await instance.database;
    return db.update(
      'items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteItem(int id) async {
    final db = await instance.database;
    return await db.delete(
      'items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('items');
  }
}
''');
  }

  static Future<void> _writeItemFeature(String targetPath) async {
    // 1. Model
    final modelFile = File('$targetPath/lib/features/items/models/item_model.dart');
    await modelFile.parent.create(recursive: true);
    await modelFile.writeAsString('''
class ItemModel {
  final int? id;
  final String title;
  final String description;
  final bool isCompleted;
  final DateTime createdAt;

  const ItemModel({
    this.id,
    required this.title,
    required this.description,
    this.isCompleted = false,
    required this.createdAt,
  });

  ItemModel copyWith({
    int? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return ItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      description: map['description'] as String,
      isCompleted: (map['isCompleted'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
''');

    // 2. Provider (State Manager with Provider)
    final providerFile = File('$targetPath/lib/features/items/providers/item_provider.dart');
    await providerFile.parent.create(recursive: true);
    await providerFile.writeAsString('''
import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import '../models/item_model.dart';

class ItemProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  List<ItemModel> _items = [];
  bool _isLoading = true;
  String _searchQuery = '';

  List<ItemModel> get items {
    if (_searchQuery.isEmpty) return _items;
    return _items
        .where((item) =>
            item.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            item.description.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  bool get isLoading => _isLoading;
  int get totalCount => _items.length;
  int get completedCount => _items.where((i) => i.isCompleted).length;

  ItemProvider() {
    loadItems();
  }

  Future<void> loadItems() async {
    _isLoading = true;
    notifyListeners();

    _items = await _db.getAllItems();
    _isLoading = false;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> addItem(String title, String description) async {
    final newItem = ItemModel(
      title: title,
      description: description,
      createdAt: DateTime.now(),
    );
    final saved = await _db.createItem(newItem);
    _items.insert(0, saved);
    notifyListeners();
  }

  Future<void> toggleItem(ItemModel item) async {
    final updated = item.copyWith(isCompleted: !item.isCompleted);
    await _db.updateItem(updated);
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      _items[index] = updated;
      notifyListeners();
    }
  }

  Future<void> deleteItem(int id) async {
    await _db.deleteItem(id);
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _db.clearAll();
    _items.clear();
    notifyListeners();
  }
}
''');
  }

  static Future<void> _writeSettingsFeature(String targetPath) async {
    final file = File('$targetPath/lib/features/settings/providers/settings_provider.dart');
    await file.parent.create(recursive: true);

    await file.writeAsString('''
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode');
    if (themeIndex != null && themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }
}
''');
  }

  static Future<void> _writeScreens(String targetPath, ProjectConfig config) async {
    // 1. Items Screen (Home Screen)
    final itemsFile = File('$targetPath/lib/features/items/presentation/items_screen.dart');
    await itemsFile.parent.create(recursive: true);
    await itemsFile.writeAsString('''
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/item_model.dart';
import '../providers/item_provider.dart';

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key});

  void _showAddDialog(BuildContext context) {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Record'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Description / Notes', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                context.read<ItemProvider>().addItem(
                      titleController.text.trim(),
                      descController.text.trim(),
                    );
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Save to SQLite'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ItemProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('${config.projectName}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SearchBar(
              hintText: 'Search offline records...',
              leading: const Icon(Icons.search),
              onChanged: (val) => context.read<ItemProvider>().setSearchQuery(val),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Item'),
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storage_rounded, size: 64, color: theme.colorScheme.primary.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text('No local records found', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('Tap "New Item" to insert into local SQLite.', style: theme.textTheme.bodySmall),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.items.length,
                  itemBuilder: (context, index) {
                    final item = provider.items[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: IconButton(
                          icon: Icon(
                            item.isCompleted ? Icons.check_circle : Icons.circle_outlined,
                            color: item.isCompleted ? Colors.green : null,
                          ),
                          onPressed: () => provider.toggleItem(item),
                        ),
                        title: Text(
                          item.title,
                          style: TextStyle(
                            decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(item.description),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => provider.deleteItem(item.id!),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
''');

    // 2. Settings Screen
    final settingsFile = File('$targetPath/lib/features/settings/presentation/settings_screen.dart');
    await settingsFile.parent.create(recursive: true);
    await settingsFile.writeAsString('''
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../items/providers/item_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final items = context.watch<ItemProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Offline Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Theme Preferences (Persistent)', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('System Default'),
                  value: ThemeMode.system,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light Mode'),
                  value: ThemeMode.light,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark Mode'),
                  value: ThemeMode.dark,
                  groupValue: settings.themeMode,
                  onChanged: (val) => settings.setThemeMode(val!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Database Storage', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.storage_rounded),
                  title: const Text('Total Stored Items'),
                  trailing: Text('\${items.totalCount}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_rounded, color: Colors.red),
                  title: const Text('Clear All SQLite Data', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear All Data?'),
                        content: const Text('This will delete all local SQLite rows permanently.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete All')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await items.clearAll();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
''');

    // 3. Shell Screen (Tabs, Drawer, or AdaptiveRail)
    final shellFile = File('$targetPath/lib/features/home/presentation/shell_screen.dart');
    await shellFile.parent.create(recursive: true);
    await shellFile.writeAsString(_generateShellCode(config));
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
          NavigationDestination(icon: Icon(Icons.list_alt_rounded), label: 'Records'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
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
            child: Text('Local Utility', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          NavigationDrawerDestination(icon: Icon(Icons.list_alt_rounded), label: Text('Records')),
          NavigationDrawerDestination(icon: Icon(Icons.settings_outlined), label: Text('Settings')),
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
                    NavigationRailDestination(icon: Icon(Icons.list_alt_rounded), label: Text('Records')),
                    NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: Text('Settings')),
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
              NavigationDestination(icon: Icon(Icons.list_alt_rounded), label: 'Records'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
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
    final file = File('$targetPath/lib/core/router/app_router.dart');
    await file.parent.create(recursive: true);

    await file.writeAsString('''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/items/presentation/items_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/home/presentation/shell_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/items',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ShellScreen(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/items',
              builder: (context, state) => const ItemsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
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
    final file = File('$targetPath/lib/main.dart');
    await file.parent.create(recursive: true);

    await file.writeAsString('''
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/items/providers/item_provider.dart';
import 'features/settings/providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ItemProvider()),
      ],
      child: const OfflineApp(),
    ),
  );
}

class OfflineApp extends StatelessWidget {
  const OfflineApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp.router(
      title: '${config.projectName}',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
    );
  }
}
''');
  }
}
