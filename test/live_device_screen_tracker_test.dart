import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flrd/features/projects/models/registered_project.dart';
import 'package:flrd/features/studio/models/route_node.dart';
import 'package:flrd/features/studio/presentation/app_studio_screen.dart';
import 'package:flrd/features/studio/providers/android_debug_provider.dart';
import 'package:flrd/features/studio/providers/studio_provider.dart';
import 'package:flrd/features/studio/services/android_device_runner_service.dart';
import 'package:flrd/features/studio/services/live_device_screen_tracker_service.dart';
import 'package:flrd/features/wizard/models/project_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeVmChannel implements VmServiceChannel {
  final StreamController<dynamic> incoming =
      StreamController<dynamic>.broadcast();
  final List<Map<String, dynamic>> sentMessages = [];
  bool closed = false;

  Map<String, dynamic> Function(String method, Map<String, dynamic> params)?
      rpcHandler;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  void send(String data) {
    final decoded = jsonDecode(data) as Map<String, dynamic>;
    sentMessages.add(decoded);

    final id = decoded['id'];
    final method = decoded['method']?.toString() ?? '';
    final params = decoded['params'] is Map<String, dynamic>
        ? decoded['params'] as Map<String, dynamic>
        : const <String, dynamic>{};

    if (rpcHandler != null) {
      final result = rpcHandler!(method, params);
      scheduleMicrotask(() {
        if (!incoming.isClosed) {
          incoming.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
        }
      });
    }
  }

  void pushNavigationEvent(String routeDescription) {
    if (!incoming.isClosed) {
      incoming.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'streamNotify',
          'params': {
            'streamId': 'Extension',
            'event': {
              'kind': 'Extension',
              'extensionKind': 'Flutter.Navigation',
              'extensionData': {
                'route': {'description': routeDescription},
              },
            },
          },
        }),
      );
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!incoming.isClosed) {
      await incoming.close();
    }
  }
}

class _FakeSink implements IOSink {
  final Completer<void> _done = Completer<void>();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  void write(Object? object) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;
}

class _FakeProc implements Process {
  final StreamController<List<int>> out =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> err =
      StreamController<List<int>>.broadcast();
  final _FakeSink sink = _FakeSink();
  final Completer<int> _exit = Completer<int>();

  @override
  int get pid => 77777;

  void emitLine(String line) {
    if (!out.isClosed) out.add(utf8.encode('$line\n'));
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => out.stream;

  @override
  Stream<List<int>> get stderr => err.stream;

  @override
  IOSink get stdin => sink;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }

  Future<void> dispose() async {
    await sink.close();
    if (!out.isClosed) await out.close();
    if (!err.isClosed) await err.close();
  }
}

Map<String, dynamic> _buildTabTree({required bool settingsVisible}) {
  return {
    'description': 'MyApp',
    'widgetRuntimeType': 'MyApp',
    'createdByLocalProject': true,
    'creationLocation': {'file': 'file:///C:/Projects/demo/lib/main.dart'},
    'children': [
      {
        'description': 'ShellScreen',
        'widgetRuntimeType': 'ShellScreen',
        'createdByLocalProject': true,
        'creationLocation': {
          'file': 'file:///C:/Projects/demo/lib/features/shell/shell_screen.dart',
        },
        'children': [
          {
            'description': 'IndexedStack',
            'widgetRuntimeType': 'IndexedStack',
            'children': [
              {
                'description': 'Offstage',
                'widgetRuntimeType': 'Offstage',
                'offstage': settingsVisible,
                'children': [
                  {
                    'description': 'HomePage',
                    'widgetRuntimeType': 'HomePage',
                    'createdByLocalProject': true,
                    'creationLocation': {
                      'file':
                          'file:///C:/Projects/demo/lib/features/home/presentation/home_page.dart',
                    },
                  },
                ],
              },
              {
                'description': 'Offstage',
                'widgetRuntimeType': 'Offstage',
                'offstage': !settingsVisible,
                'children': [
                  {
                    'description': 'SettingsPage',
                    'widgetRuntimeType': 'SettingsPage',
                    'createdByLocalProject': true,
                    'creationLocation': {
                      'file':
                          'file:///C:/Projects/demo/lib/features/settings/presentation/settings_page.dart',
                    },
                  },
                ],
              },
            ],
          },
        ],
      },
    ],
  };
}

void main() {
  group('LiveDeviceScreenTrackerService', () {
    test('normalizes VM Service URIs and inspector file paths cross-platform', () {
      expect(
        LiveDeviceScreenTrackerService.normalizeVmServiceWsUri(
          'http://127.0.0.1:51234/abc=/',
        )?.toString(),
        'ws://127.0.0.1:51234/abc=/ws',
      );
      expect(
        LiveDeviceScreenTrackerService.normalizeVmServiceWsUri(
          'ws://127.0.0.1:51234/abc=/ws',
        )?.toString(),
        'ws://127.0.0.1:51234/abc=/ws',
      );

      expect(
        LiveDeviceScreenTrackerService.normalizeInspectorFilePath(
          'file:///C:/Projects/demo/lib/features/home/presentation/home_page.dart',
          projectPath: r'C:\Projects\demo',
        ),
        'lib/features/home/presentation/home_page.dart',
      );
      expect(
        LiveDeviceScreenTrackerService.normalizeInspectorFilePath(
          'package:demo_app/features/settings/presentation/settings_page.dart',
          projectPackageName: 'demo_app',
        ),
        'lib/features/settings/presentation/settings_page.dart',
      );
      expect(
        LiveDeviceScreenTrackerService.normalizeInspectorFilePath(
          'file:///C:/src/flutter/packages/flutter/lib/src/material/scaffold.dart',
        ),
        isNull,
      );
    });

    test('skips Offstage hidden tabs and ranks active content page ahead of ShellScreen and main.dart', () {
      final homeSnap = LiveDeviceScreenTrackerService.extractSnapshotFromSummaryTree(
        _buildTabTree(settingsVisible: false),
        projectPath: r'C:\Projects\demo',
      );
      expect(homeSnap.widgetName, 'HomePage');
      expect(
        homeSnap.filePath,
        'lib/features/home/presentation/home_page.dart',
      );

      final settingsSnap =
          LiveDeviceScreenTrackerService.extractSnapshotFromSummaryTree(
        _buildTabTree(settingsVisible: true),
        projectPath: r'C:\Projects\demo',
      );
      expect(settingsSnap.widgetName, 'SettingsPage');
      expect(
        settingsSnap.filePath,
        'lib/features/settings/presentation/settings_page.dart',
      );
    });

    test('matches RouteNode by filePath, basename, routeName, or title', () {
      const nodes = <RouteNode>[
        RouteNode(
          id: 'home',
          path: '/home',
          title: 'Home',
          subtitle: 'Main Home',
          icon: Icons.home_rounded,
          position: Offset(100, 100),
          filePath: 'lib/features/home/presentation/home_page.dart',
        ),
        RouteNode(
          id: 'settings',
          path: '/settings',
          title: 'Settings',
          subtitle: 'Preferences',
          icon: Icons.settings_rounded,
          position: Offset(420, 100),
          filePath: 'lib/features/settings/presentation/settings_page.dart',
        ),
      ];

      final byFile = LiveDeviceScreenSnapshot(
        filePath: 'lib/features/settings/presentation/settings_page.dart',
        widgetName: 'SettingsPage',
        updatedAt: DateTime(2026),
      );
      expect(
        LiveDeviceScreenTrackerService.matchRouteNode(byFile, nodes)?.id,
        'settings',
      );

      final byRoute = LiveDeviceScreenSnapshot(
        routeName: '/settings?section=account',
        updatedAt: DateTime(2026),
      );
      expect(
        LiveDeviceScreenTrackerService.matchRouteNode(byRoute, nodes)?.id,
        'settings',
      );
    });

    test('connects via VM Service RPC, disposes inspector group, and updates on Flutter.Navigation', () async {
      final channel = _FakeVmChannel();
      var onSettings = false;
      channel.rpcHandler = (method, params) {
        if (method == 'getVM') {
          return {
            'isolates': [
              {'id': 'isolates/1', 'name': 'main'},
            ],
          };
        }
        if (method == 'streamListen') return {'type': 'Success'};
        if (method == 'ext.flutter.inspector.getRootWidgetSummaryTree') {
          return {'result': _buildTabTree(settingsVisible: onSettings)};
        }
        if (method == 'ext.flutter.inspector.disposeGroup') {
          return {'result': true};
        }
        return const {};
      };

      final tracker = LiveDeviceScreenTrackerService(
        connector: (_) async => channel,
        pollInterval: const Duration(hours: 1),
      );
      addTearDown(tracker.dispose);

      final received = <LiveDeviceScreenSnapshot>[];
      final sub = tracker.updates.listen(received.add);
      addTearDown(sub.cancel);

      await tracker.start(
        vmServiceUri: 'ws://127.0.0.1:50000/token=/ws',
        projectPath: r'C:\Projects\demo',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(received, isNotEmpty);
      expect(received.last.widgetName, 'HomePage');
      expect(
        channel.sentMessages
            .any((m) => m['method'] == 'ext.flutter.inspector.disposeGroup'),
        isTrue,
      );

      // Simulate user navigating to /settings on the connected phone
      onSettings = true;
      channel.pushNavigationEvent('/settings');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(received.last.widgetName, 'SettingsPage');
      expect(received.last.routeName, '/settings');
      expect(
        received.last.filePath,
        'lib/features/settings/presentation/settings_page.dart',
      );
    });

    testWidgets(
      'AppStudioScreen indicates live phone screen without hijacking user selection, and jumps on click',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final tempProj = Directory.systemTemp.createTempSync('flrd_live_track_');
        File(p.join(tempProj.path, 'pubspec.yaml'))
            .writeAsStringSync('name: demo\nversion: 1.0.0\n');
        File(p.join(tempProj.path, 'lib', 'features', 'home', 'presentation', 'home_page.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('class HomePage {}\n');
        File(p.join(tempProj.path, 'lib', 'features', 'settings', 'presentation', 'settings_page.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('class SettingsPage {}\n');

        final fakeProc = _FakeProc();
        final fakeChannel = _FakeVmChannel();
        var onSettings = false;
        fakeChannel.rpcHandler = (method, params) {
          if (method == 'getVM') {
            return {
              'isolates': [
                {'id': 'isolates/1', 'name': 'main'},
              ],
            };
          }
          if (method == 'streamListen') return {'type': 'Success'};
          if (method == 'ext.flutter.inspector.getRootWidgetSummaryTree') {
            return {'result': _buildTabTree(settingsVisible: onSettings)};
          }
          return {'result': true};
        };

        addTearDown(() async {
          await fakeProc.dispose();
          if (tempProj.existsSync()) tempProj.deleteSync(recursive: true);
        });

        final fakeRunner = AndroidDeviceRunnerService(
          processRunner: (exec, args, {workingDirectory, runInShell = true}) async {
            if (exec == 'flutter' && args.isNotEmpty && args.first == 'devices') {
              return ProcessResult(
                1,
                0,
                jsonEncode([
                  {
                    'name': 'SM S938B',
                    'id': 'RXGL20BSBJX',
                    'isSupported': true,
                    'targetPlatform': 'android-arm64',
                    'emulator': false,
                    'sdk': 'Android 16',
                  },
                ]),
                '',
              );
            }
            if (exec == 'taskkill') {
              fakeProc.kill();
              return ProcessResult(2, 0, '', '');
            }
            return ProcessResult(3, 0, '', '');
          },
          processStarter: (exec, args, {workingDirectory, runInShell = true}) async =>
              fakeProc,
        );

        final container = ProviderContainer(
          overrides: [
            androidDeviceRunnerServiceProvider.overrideWithValue(fakeRunner),
            liveScreenTrackerFactoryProvider.overrideWithValue(
              () => LiveDeviceScreenTrackerService(
                connector: (_) async => fakeChannel,
                pollInterval: const Duration(hours: 1),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(studioProvider.notifier).setNodes(const [
          RouteNode(
            id: 'home',
            path: '/home',
            title: 'Home',
            subtitle: 'Home screen',
            icon: Icons.home_rounded,
            position: Offset(100, 120),
            filePath: 'lib/features/home/presentation/home_page.dart',
          ),
          RouteNode(
            id: 'settings',
            path: '/settings',
            title: 'Settings',
            subtitle: 'Settings screen',
            icon: Icons.settings_rounded,
            position: Offset(440, 120),
            filePath: 'lib/features/settings/presentation/settings_page.dart',
          ),
        ]);
        // User explicitly chooses to edit Home in FLRD
        container.read(studioProvider.notifier).selectNode('home');

        final project = RegisteredProject(
          id: 'proj-live-track',
          name: 'demo',
          orgId: 'com.example',
          path: tempProj.path,
          preset: PresetType.cleanLite,
          navigationStyle: NavigationStyle.tabs,
          permissions: const {},
          lastModified: DateTime(2026),
          routeCount: 2,
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(home: AppStudioScreen(project: project)),
          ),
        );
        await tester.pumpAndSettle();

        // Scan and launch on SM S938B
        await tester
            .tap(find.byKey(const ValueKey('android_scan_devices_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('android_launch_button')));
        await tester.pumpAndSettle();

        fakeProc.emitLine(
          '[{"event":"app.start","params":{"appId":"app-track-1"}}]',
        );
        fakeProc.emitLine(
          '[{"event":"app.debugPort","params":{"appId":"app-track-1","wsUri":"ws://127.0.0.1:50000/ws"}}]',
        );
        fakeProc.emitLine(
          '[{"event":"app.started","params":{"appId":"app-track-1"}}]',
        );
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // Phone is initially on Home (matching user's current selection)
        expect(
          find.byKey(const ValueKey('live_device_screen_banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('live_device_badge_home')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('live_device_matching_selection_badge')),
          findsOneWidget,
        );

        // Phone navigates to Settings while user stays editing Home
        onSettings = true;
        fakeChannel.pushNavigationEvent('/settings');
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();

        // CRITICAL: FLRD must NOT hijack user's selected node!
        expect(container.read(studioProvider).selectedNodeId, 'home');
        expect(
          find.byKey(const ValueKey('live_device_badge_settings')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('jump_to_live_device_screen_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('open_live_device_code_button')),
          findsOneWidget,
        );

        // User opts in to jump directly to Settings code
        await tester
            .tap(find.byKey(const ValueKey('open_live_device_code_button')));
        await tester.pumpAndSettle();

        expect(container.read(studioProvider).selectedNodeId, 'settings');
        expect(
          find.byKey(const ValueKey('live_device_matching_selection_badge')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('jump_to_live_device_screen_button')),
          findsNothing,
        );

        // Stop session -> live screen banner and badge disappear cleanly
        await tester.tap(find.byKey(const ValueKey('android_stop_button')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('live_device_screen_banner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('live_device_badge_settings')),
          findsNothing,
        );
      },
    );
  });
}
