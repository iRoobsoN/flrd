import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/route_node.dart';

/// Immutable snapshot describing which screen/widget is currently visible on
/// the connected Android device, inferred from the Dart VM Service and Flutter
/// Widget Inspector without mutating the target application.
@immutable
class LiveDeviceScreenSnapshot {
  final String? routeName;
  final String? widgetName;
  final String? filePath;
  final List<String> activeProjectFiles;
  final List<String> activeWidgetNames;
  final DateTime updatedAt;

  const LiveDeviceScreenSnapshot({
    this.routeName,
    this.widgetName,
    this.filePath,
    this.activeProjectFiles = const [],
    this.activeWidgetNames = const [],
    required this.updatedAt,
  });

  bool get hasLocation =>
      (filePath != null && filePath!.trim().isNotEmpty) ||
      (widgetName != null && widgetName!.trim().isNotEmpty) ||
      (routeName != null && routeName!.trim().isNotEmpty);

  String get displayLabel {
    final w = widgetName?.trim();
    if (w != null && w.isNotEmpty) return w;
    final f = filePath?.trim();
    if (f != null && f.isNotEmpty) {
      return p.posix.basenameWithoutExtension(f.replaceAll('\\', '/'));
    }
    final r = routeName?.trim();
    if (r != null && r.isNotEmpty) return r;
    return 'Tela ativa';
  }

  LiveDeviceScreenSnapshot copyWith({
    String? routeName,
    String? widgetName,
    String? filePath,
    List<String>? activeProjectFiles,
    List<String>? activeWidgetNames,
    DateTime? updatedAt,
  }) {
    return LiveDeviceScreenSnapshot(
      routeName: routeName ?? this.routeName,
      widgetName: widgetName ?? this.widgetName,
      filePath: filePath ?? this.filePath,
      activeProjectFiles: activeProjectFiles ?? this.activeProjectFiles,
      activeWidgetNames: activeWidgetNames ?? this.activeWidgetNames,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Semantic equality ignores [updatedAt] so identical periodic polls do not
  /// trigger unnecessary widget rebuilds.
  bool sameScreenAs(LiveDeviceScreenSnapshot? other) {
    if (other == null) return false;
    return routeName == other.routeName &&
        widgetName == other.widgetName &&
        filePath == other.filePath &&
        listEquals(activeProjectFiles, other.activeProjectFiles);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LiveDeviceScreenSnapshot &&
        other.routeName == routeName &&
        other.widgetName == widgetName &&
        other.filePath == filePath &&
        listEquals(other.activeProjectFiles, activeProjectFiles) &&
        listEquals(other.activeWidgetNames, activeWidgetNames);
  }

  @override
  int get hashCode => Object.hash(
        routeName,
        widgetName,
        filePath,
        Object.hashAll(activeProjectFiles),
        Object.hashAll(activeWidgetNames),
      );
}

/// Minimal WebSocket channel abstraction so [LiveDeviceScreenTrackerService]
/// can be unit-tested cleanly without opening real sockets.
abstract class VmServiceChannel {
  Stream<dynamic> get stream;
  void send(String data);
  Future<void> close();
}

class _IoWebSocketChannel implements VmServiceChannel {
  final WebSocket _socket;

  _IoWebSocketChannel(this._socket);

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void send(String data) {
    if (_socket.readyState == WebSocket.open) {
      _socket.add(data);
    }
  }

  @override
  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {}
  }
}

typedef VmServiceChannelConnector = Future<VmServiceChannel> Function(Uri uri);

/// Connects read-only to a running Flutter app's Dart VM Service WebSocket,
/// listens for `Flutter.Navigation` extension events, and periodically queries
/// `ext.flutter.inspector.getRootWidgetSummaryTree` to detect the active screen
/// (covering both Navigator/go_router routes and BottomNavigationBar/TabBar tabs).
class LiveDeviceScreenTrackerService {
  static const String _inspectorGroup = 'flrd_live_screen_tracker';

  final VmServiceChannelConnector _connector;
  final Duration _pollInterval;

  final StreamController<LiveDeviceScreenSnapshot> _controller =
      StreamController<LiveDeviceScreenSnapshot>.broadcast();

  VmServiceChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _pollTimer;
  String? _isolateId;
  String? _projectPath;
  String? _projectPackageName;
  String? _lastKnownRouteName;
  LiveDeviceScreenSnapshot? _lastEmitted;
  int _nextRpcId = 1;
  bool _disposed = false;
  bool _isRefreshing = false;

  final Map<int, Completer<Map<String, dynamic>>> _pendingRpcs = {};

  LiveDeviceScreenTrackerService({
    VmServiceChannelConnector? connector,
    Duration pollInterval = const Duration(milliseconds: 1500),
  })  : _connector = connector ?? _defaultConnect,
        _pollInterval = pollInterval;

  static Future<VmServiceChannel> _defaultConnect(Uri uri) async {
    final socket = await WebSocket.connect(uri.toString())
        .timeout(const Duration(seconds: 5));
    return _IoWebSocketChannel(socket);
  }

  Stream<LiveDeviceScreenSnapshot> get updates => _controller.stream;

  LiveDeviceScreenSnapshot? get latestSnapshot => _lastEmitted;

  /// Normalizes a Flutter daemon `wsUri` or `http://` observatory URI into a
  /// Dart VM Service WebSocket URI ending in `/ws`.
  static Uri? normalizeVmServiceWsUri(String? rawUri) {
    final clean = rawUri?.trim();
    if (clean == null || clean.isEmpty) return null;
    final parsed = Uri.tryParse(clean);
    if (parsed == null || parsed.host.isEmpty) return null;

    var scheme = parsed.scheme.toLowerCase();
    if (scheme == 'http') {
      scheme = 'ws';
    } else if (scheme == 'https') {
      scheme = 'wss';
    } else if (scheme != 'ws' && scheme != 'wss') {
      return null;
    }

    var path = parsed.path;
    if (!path.endsWith('/ws')) {
      if (path.endsWith('/')) {
        path = '${path}ws';
      } else {
        path = '$path/ws';
      }
    }

    return parsed.replace(scheme: scheme, path: path);
  }

  /// Starts tracking the connected device app exposed at [vmServiceUri].
  Future<void> start({
    required String vmServiceUri,
    String? projectPath,
    String? projectPackageName,
  }) async {
    if (_disposed) return;
    await stop();
    if (_disposed) return;

    final wsUri = normalizeVmServiceWsUri(vmServiceUri);
    if (wsUri == null) return;

    _projectPath = projectPath?.trim();
    _projectPackageName = projectPackageName?.trim().isNotEmpty == true
        ? projectPackageName!.trim()
        : _readPubspecName(_projectPath);
    _lastKnownRouteName = null;
    _lastEmitted = null;

    try {
      final channel = await _connector(wsUri);
      if (_disposed) {
        await channel.close();
        return;
      }
      _channel = channel;
      _socketSub = channel.stream.listen(
        _handleSocketMessage,
        onError: (_) {},
        onDone: () {
          _pollTimer?.cancel();
          _pollTimer = null;
          _failPendingRpcs();
        },
      );

      final vmResp = await _callRpc('getVM');
      _isolateId = _extractMainIsolateId(vmResp);
      if (_isolateId == null || _disposed) return;

      // Subscribe to Flutter extension events (includes Flutter.Navigation).
      try {
        await _callRpc('streamListen', {'streamId': 'Extension'});
      } catch (_) {}

      await refreshNow();
      if (_disposed) return;

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollInterval, (_) {
        unawaited(refreshNow());
      });
    } catch (_) {
      // Never disrupt an active Android debug session if VM Service tracking fails.
    }
  }

  /// Queries the live Flutter widget summary tree once and emits an update if
  /// the visible screen changed.
  Future<void> refreshNow() async {
    if (_disposed || _isRefreshing || _channel == null || _isolateId == null) {
      return;
    }
    _isRefreshing = true;
    try {
      final treeResp = await _callRpc(
        'ext.flutter.inspector.getRootWidgetSummaryTree',
        {
          'isolateId': _isolateId,
          'groupName': _inspectorGroup,
          'includeProperties': 'false',
        },
      );

      // Always dispose inspector object group immediately so the device VM
      // never accumulates widget references across periodic polls.
      unawaited(
        _callRpc(
          'ext.flutter.inspector.disposeGroup',
          {
            'isolateId': _isolateId,
            'groupName': _inspectorGroup,
          },
        ).catchError((_) => <String, dynamic>{}),
      );

      final root = treeResp['result'];
      if (root is Map<String, dynamic>) {
        final snapshot = extractSnapshotFromSummaryTree(
          root,
          projectPath: _projectPath,
          projectPackageName: _projectPackageName,
          routeName: _lastKnownRouteName,
        );
        if (snapshot.hasLocation) {
          _emitIfChanged(snapshot);
        }
      }
    } catch (_) {
      // Ignore transient inspector failures (e.g. mid-Hot Reload).
    } finally {
      _isRefreshing = false;
    }
  }

  /// Stops polling and closes the VM Service WebSocket connection.
  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    _failPendingRpcs();
    final ch = _channel;
    _channel = null;
    _isolateId = null;
    _isRefreshing = false;
    if (ch != null) {
      await ch.close();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void _handleSocketMessage(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return;
    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return;
      decoded = parsed;
    } catch (_) {
      return;
    }

    // 1. JSON-RPC response to one of our calls.
    final idRaw = decoded['id'];
    if (idRaw != null) {
      final id = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
      if (id != null && _pendingRpcs.containsKey(id)) {
        final completer = _pendingRpcs.remove(id)!;
        if (decoded['error'] != null) {
          completer.completeError(decoded['error']!);
        } else {
          final result = decoded['result'];
          completer.complete(
            result is Map<String, dynamic>
                ? result
                : <String, dynamic>{'value': result},
          );
        }
      }
      return;
    }

    // 2. Stream notification (`streamNotify`) from Dart VM Service.
    if (decoded['method'] == 'streamNotify') {
      final params = decoded['params'];
      if (params is! Map<String, dynamic>) return;
      final event = params['event'];
      if (event is! Map<String, dynamic>) return;

      final extensionKind = event['extensionKind']?.toString();
      if (extensionKind == 'Flutter.Navigation') {
        final extData = event['extensionData'];
        if (extData is Map<String, dynamic>) {
          final route = extData['route'];
          String? routeDesc;
          if (route is Map<String, dynamic>) {
            routeDesc = route['description']?.toString().trim();
          } else if (route is String) {
            routeDesc = route.trim();
          }
          if (routeDesc != null &&
              routeDesc.isNotEmpty &&
              routeDesc != 'null') {
            _lastKnownRouteName = _normalizeRouteName(routeDesc);
            if (_lastEmitted != null) {
              _emitIfChanged(
                _lastEmitted!.copyWith(
                  routeName: _lastKnownRouteName,
                  updatedAt: DateTime.now(),
                ),
              );
            } else {
              _emitIfChanged(
                LiveDeviceScreenSnapshot(
                  routeName: _lastKnownRouteName,
                  updatedAt: DateTime.now(),
                ),
              );
            }
          }
        }
        // Immediately refresh the widget tree so tab/route widget file updates
        // without waiting for the next periodic poll tick.
        unawaited(refreshNow());
      }
    }
  }

  Future<Map<String, dynamic>> _callRpc(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final ch = _channel;
    if (ch == null) {
      return Future<Map<String, dynamic>>.error(
        StateError('VM Service channel not connected'),
      );
    }
    final id = _nextRpcId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRpcs[id] = completer;

    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null && params.isNotEmpty) 'params': params,
    };
    ch.send(jsonEncode(payload));

    return completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _pendingRpcs.remove(id);
        throw TimeoutException('VM Service RPC timeout ($method)');
      },
    );
  }

  void _failPendingRpcs() {
    for (final completer in _pendingRpcs.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('VM Service connection closed'));
      }
    }
    _pendingRpcs.clear();
  }

  void _emitIfChanged(LiveDeviceScreenSnapshot snapshot) {
    if (_disposed || _controller.isClosed) return;
    if (_lastEmitted != null && _lastEmitted!.sameScreenAs(snapshot)) {
      return;
    }
    _lastEmitted = snapshot;
    _controller.add(snapshot);
  }

  static String? _extractMainIsolateId(Map<String, dynamic> vmResp) {
    final isolates = vmResp['isolates'];
    if (isolates is! List || isolates.isEmpty) return null;
    for (final item in isolates) {
      if (item is Map<String, dynamic>) {
        final name = (item['name'] ?? '').toString().toLowerCase();
        final id = item['id']?.toString();
        if (id != null && id.isNotEmpty && name.contains('main')) {
          return id;
        }
      }
    }
    final first = isolates.first;
    if (first is Map<String, dynamic>) {
      return first['id']?.toString();
    }
    return null;
  }

  static String? _readPubspecName(String? projectPath) {
    if (projectPath == null || projectPath.isEmpty) return null;
    try {
      final file = File(p.join(projectPath, 'pubspec.yaml'));
      if (!file.existsSync()) return null;
      final content = file.readAsStringSync();
      final match = RegExp(r'^\s*name\s*:\s*([a-zA-Z0-9_]+)', multiLine: true)
          .firstMatch(content);
      return match?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  static String _normalizeRouteName(String raw) {
    final clean = raw.trim();
    final qIdx = clean.indexOf('?');
    final withoutQuery = qIdx >= 0 ? clean.substring(0, qIdx) : clean;
    if (withoutQuery.isEmpty) return '/';
    return withoutQuery;
  }

  /// Extracts the active screen snapshot from an
  /// `ext.flutter.inspector.getRootWidgetSummaryTree` JSON root node.
  ///
  /// Skips hidden `Offstage(offstage: true)` / `TickerMode(disabled)` subtrees
  /// (critical for `IndexedStack` / `NavigationBar` / `TabBarView` tabs) and
  /// ranks deepest visible project screen files ahead of app shells & `main.dart`.
  static LiveDeviceScreenSnapshot extractSnapshotFromSummaryTree(
    Map<String, dynamic> rootNode, {
    String? projectPath,
    String? projectPackageName,
    String? routeName,
    DateTime? now,
  }) {
    final candidates = <({String filePath, String widgetName, int depth})>[];

    void walk(Map<String, dynamic> node, int depth) {
      if (_isHiddenSubtree(node)) return;

      final children = node['children'];
      if (children is List) {
        for (final child in children) {
          if (child is Map<String, dynamic>) {
            walk(child, depth + 1);
          }
        }
      }

      final createdByLocal = node['createdByLocalProject'] == true;
      final location = node['creationLocation'];
      final rawFile = location is Map<String, dynamic>
          ? location['file']?.toString()
          : null;
      final relFile = normalizeInspectorFilePath(
        rawFile,
        projectPath: projectPath,
        projectPackageName: projectPackageName,
      );

      final widgetName = _extractWidgetName(node);
      if (relFile != null && (createdByLocal || relFile.startsWith('lib/'))) {
        candidates.add((
          filePath: relFile,
          widgetName: widgetName ??
              p.posix.basenameWithoutExtension(relFile),
          depth: depth,
        ));
      }
    }

    walk(rootNode, 0);

    if (candidates.isEmpty) {
      return LiveDeviceScreenSnapshot(
        routeName: routeName,
        updatedAt: now ?? DateTime.now(),
      );
    }

    // Deduplicate by filePath keeping deepest occurrence per screen file.
    final bestByFile =
        <String, ({String filePath, String widgetName, int depth})>{};
    for (final c in candidates) {
      final key = c.filePath.toLowerCase();
      final existing = bestByFile[key];
      if (existing == null || c.depth >= existing.depth) {
        bestByFile[key] = c;
      }
    }

    final ranked = bestByFile.values.toList()
      ..sort((a, b) {
        final scoreDiff = _screenPriorityScore(b.filePath, b.widgetName)
            .compareTo(_screenPriorityScore(a.filePath, a.widgetName));
        if (scoreDiff != 0) return scoreDiff;
        return b.depth.compareTo(a.depth);
      });

    final primary = ranked.first;
    return LiveDeviceScreenSnapshot(
      routeName: routeName,
      widgetName: primary.widgetName,
      filePath: primary.filePath,
      activeProjectFiles: ranked.map((e) => e.filePath).toList(growable: false),
      activeWidgetNames:
          ranked.map((e) => e.widgetName).toList(growable: false),
      updatedAt: now ?? DateTime.now(),
    );
  }

  /// Matches a [LiveDeviceScreenSnapshot] against the FLRD Studio's mapped
  /// [nodes] without forcing selection.
  static RouteNode? matchRouteNode(
    LiveDeviceScreenSnapshot snapshot,
    List<RouteNode> nodes,
  ) {
    if (nodes.isEmpty || !snapshot.hasLocation) return null;

    String normPath(String raw) => raw.replaceAll('\\', '/').trim().toLowerCase();

    // 1. Exact relative filePath match (walking activeProjectFiles in priority order).
    final filesToCheck = <String>[
      if (snapshot.filePath != null) snapshot.filePath!,
      ...snapshot.activeProjectFiles,
    ];
    for (final file in filesToCheck) {
      final normFile = normPath(file);
      for (final node in nodes) {
        if (node.filePath.trim().isEmpty) continue;
        final nodeFile = normPath(node.filePath);
        if (nodeFile == normFile ||
            normFile.endsWith('/$nodeFile') ||
            nodeFile.endsWith('/$normFile')) {
          return node;
        }
      }
    }

    // 2. Basename match (e.g. `settings_page.dart`).
    for (final file in filesToCheck) {
      final base = p.posix.basename(normPath(file));
      if (base.isEmpty || base == 'main.dart') continue;
      for (final node in nodes) {
        if (node.filePath.trim().isEmpty) continue;
        if (p.posix.basename(normPath(node.filePath)) == base) {
          return node;
        }
      }
    }

    // 3. Exact route path match from `Flutter.Navigation` (e.g. `/settings`).
    final route = snapshot.routeName?.trim();
    if (route != null && route.isNotEmpty) {
      final cleanRoute = _normalizeRouteName(route).toLowerCase();
      for (final node in nodes) {
        if (node.path.trim().toLowerCase() == cleanRoute) {
          return node;
        }
      }
    }

    // 4. Normalized widget class / title match (e.g. `SettingsPage` -> `Settings`).
    final widgetsToCheck = <String>[
      if (snapshot.widgetName != null) snapshot.widgetName!,
      ...snapshot.activeWidgetNames,
    ];
    for (final rawName in widgetsToCheck) {
      final token = _normalizeIdentifier(rawName);
      if (token.isEmpty) continue;
      for (final node in nodes) {
        final nodeToken = _normalizeIdentifier(node.title);
        if (nodeToken.isNotEmpty &&
            (nodeToken == token ||
                token.contains(nodeToken) ||
                nodeToken.contains(token))) {
          return node;
        }
      }
    }

    return null;
  }

  /// Normalizes a Dart VM Service `creationLocation.file` URI (`file:///...`,
  /// `package:<app>/...`, or relative path) into a project-relative `lib/...`
  /// POSIX path. Returns `null` for Flutter SDK / third-party package files.
  static String? normalizeInspectorFilePath(
    String? rawFile, {
    String? projectPath,
    String? projectPackageName,
  }) {
    if (rawFile == null || rawFile.trim().isEmpty) return null;
    var path = rawFile.trim();

    if (path.startsWith('package:')) {
      final rest = path.substring('package:'.length);
      final slashIdx = rest.indexOf('/');
      if (slashIdx <= 0) return null;
      final pkgName = rest.substring(0, slashIdx);
      if (pkgName == 'flutter' || pkgName == 'dart') return null;
      if (projectPackageName != null &&
          projectPackageName.isNotEmpty &&
          pkgName != projectPackageName) {
        return null;
      }
      return 'lib/${rest.substring(slashIdx + 1)}';
    }

    if (path.startsWith('file://')) {
      try {
        final uri = Uri.parse(path);
        path = Uri.decodeComponent(uri.path);
        // Strip leading slash on Windows URIs like `/C:/Projects/...`.
        if (RegExp(r'^/[a-zA-Z]:/').hasMatch(path)) {
          path = path.substring(1);
        }
      } catch (_) {
        path = path.replaceFirst(RegExp(r'^file:///+'), '');
      }
    }

    final posix = path.replaceAll('\\', '/');
    if (posix.contains('/packages/flutter/') ||
        posix.contains('/.pub-cache/') ||
        posix.contains('/Pub/Cache/')) {
      return null;
    }

    if (projectPath != null && projectPath.trim().isNotEmpty) {
      final normProj = projectPath.replaceAll('\\', '/').trim();
      final lowerPosix = posix.toLowerCase();
      final lowerProj = normProj.toLowerCase().endsWith('/')
          ? normProj.toLowerCase()
          : '${normProj.toLowerCase()}/';
      if (lowerPosix.startsWith(lowerProj)) {
        final rel = posix.substring(lowerProj.length);
        return rel.isNotEmpty ? rel : null;
      }
    }

    final libIdx = posix.lastIndexOf('/lib/');
    if (libIdx >= 0) {
      return posix.substring(libIdx + 1);
    }
    if (posix.startsWith('lib/')) {
      return posix;
    }
    return null;
  }

  static bool _isHiddenSubtree(Map<String, dynamic> node) {
    final desc = (node['description'] ?? '').toString().toLowerCase();
    final type = (node['widgetRuntimeType'] ?? '').toString().toLowerCase();
    if ((type == 'offstage' || desc.startsWith('offstage')) &&
        (node['offstage'] == true ||
            desc.contains('offstage: true') ||
            _hasPropertyValue(node, 'offstage', 'true'))) {
      return true;
    }
    if ((type == 'tickermode' || desc.startsWith('tickermode')) &&
        (desc.contains('disabled') ||
            _hasPropertyValue(node, 'enabled', 'false'))) {
      return true;
    }
    return false;
  }

  static bool _hasPropertyValue(
    Map<String, dynamic> node,
    String propertyName,
    String expectedValue,
  ) {
    final props = node['properties'];
    if (props is! List) return false;
    for (final prop in props) {
      if (prop is Map<String, dynamic>) {
        final name = (prop['name'] ?? '').toString().toLowerCase();
        final desc = (prop['description'] ?? '').toString().toLowerCase();
        final value = (prop['value'] ?? '').toString().toLowerCase();
        if (name == propertyName &&
            (desc == expectedValue || value == expectedValue)) {
          return true;
        }
      }
    }
    return false;
  }

  static String? _extractWidgetName(Map<String, dynamic> node) {
    final runtimeType = node['widgetRuntimeType']?.toString().trim();
    if (runtimeType != null &&
        runtimeType.isNotEmpty &&
        !runtimeType.startsWith('_')) {
      return runtimeType;
    }
    final desc = node['description']?.toString().trim();
    if (desc != null && desc.isNotEmpty) {
      final clean = desc.split(RegExp(r'[\s(\[]')).first.trim();
      if (clean.isNotEmpty) return clean;
    }
    return runtimeType;
  }

  /// Higher score means more likely to be the actual content screen rather than
  /// an outer app shell, router wrapper, or small reusable component.
  static int _screenPriorityScore(String relFilePath, String widgetName) {
    final lowerPath = relFilePath.toLowerCase();
    final lowerName = widgetName.toLowerCase();

    if (lowerPath == 'lib/main.dart' || lowerPath.endsWith('/main.dart')) {
      return 10;
    }
    if (lowerPath.contains('router') || lowerPath.contains('theme')) {
      return 15;
    }
    if (lowerPath.contains('shell') ||
        lowerName.contains('shell') ||
        lowerName.endsWith('app')) {
      return 30;
    }
    if (lowerPath.contains('/widgets/') || lowerPath.endsWith('_widget.dart')) {
      return 45;
    }
    if (lowerPath.endsWith('_screen.dart') ||
        lowerPath.endsWith('_page.dart') ||
        lowerPath.endsWith('_view.dart') ||
        lowerName.endsWith('screen') ||
        lowerName.endsWith('page') ||
        lowerName.endsWith('dashboard') ||
        lowerName.endsWith('view')) {
      return 100;
    }
    return 70;
  }

  static String _normalizeIdentifier(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'(screen|page|view|widget)$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
