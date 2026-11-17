import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../projects/models/registered_project.dart';
import '../../../projects/providers/projects_provider.dart';
import '../../services/native_permissions_service.dart';
import '../../services/pub_dev_and_dependencies_service.dart';

/// Callback signature allowing callers/tests to intercept `flutter pub get`.
typedef PubGetRunnerFn = Future<({bool success, String output})> Function(
  String projectRoot,
);

/// Unified Hub inside AppStudioScreen for searching & managing real `pubspec.yaml`
/// dependencies (connected to `pub.dev`) and manipulating real native Android/iOS
/// permissions (`AndroidManifest.xml` & `Info.plist`).
class ProjectPackagesPermissionsHub extends ConsumerStatefulWidget {
  final RegisteredProject project;
  final ValueChanged<RegisteredProject>? onProjectUpdated;
  final PubGetRunnerFn? pubGetRunner;

  const ProjectPackagesPermissionsHub({
    super.key,
    required this.project,
    this.onProjectUpdated,
    this.pubGetRunner,
  });

  @override
  ConsumerState<ProjectPackagesPermissionsHub> createState() =>
      _ProjectPackagesPermissionsHubState();
}

class _ProjectPackagesPermissionsHubState
    extends ConsumerState<ProjectPackagesPermissionsHub> {
  // Dependencies state
  late PubspecDependenciesSnapshot _depsSnapshot;
  final TextEditingController _pubSearchController = TextEditingController();
  final TextEditingController _manualPkgNameController = TextEditingController();
  final TextEditingController _manualPkgVersionController =
      TextEditingController();
  bool _manualIsDev = false;
  bool _highRatedOnly = true;
  bool _favoritesOnly = false;
  PubDevSort _sort = PubDevSort.top;
  bool _isSearchingPubDev = false;
  bool _isRunningPubGet = false;
  PubDevSearchResult? _pubSearchResult;

  // Permissions state
  late ProjectPermissionsSnapshot _permsSnapshot;
  final TextEditingController _customAndroidPermController =
      TextEditingController();
  final TextEditingController _customIosKeyController = TextEditingController();
  final TextEditingController _customIosReasonController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _reloadDiskSnapshots();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _performPubDevSearch('');
      }
    });
  }

  @override
  void didUpdateWidget(covariant ProjectPackagesPermissionsHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.path != widget.project.path) {
      _reloadDiskSnapshots();
    }
  }

  @override
  void dispose() {
    _pubSearchController.dispose();
    _manualPkgNameController.dispose();
    _manualPkgVersionController.dispose();
    _customAndroidPermController.dispose();
    _customIosKeyController.dispose();
    _customIosReasonController.dispose();
    super.dispose();
  }

  void _reloadDiskSnapshots() {
    _depsSnapshot = PubspecDependenciesService.readDependencies(
      widget.project.path,
    );
    _permsSnapshot = NativePermissionsService.readPermissions(
      widget.project.path,
    );
  }

  void _refreshAndSyncProject() {
    setState(() {
      _reloadDiskSnapshots();
    });
    final syncedPerms =
        NativePermissionsService.computeDetectedDevicePermissions(_permsSnapshot);
    final updatedProject = widget.project.copyWith(permissions: syncedPerms);
    ref.read(projectsProvider.notifier).registerProject(updatedProject);
    widget.onProjectUpdated?.call(updatedProject);
  }

  Future<void> _performPubDevSearch(String query) async {
    if (!mounted) return;
    setState(() => _isSearchingPubDev = true);

    final injectedClient = ref.read(pubDevHttpClientProvider);
    final result = await PubDevService.searchPackages(
      query,
      sort: _sort,
      highRatedOnly: _highRatedOnly,
      favoritesOnly: _favoritesOnly,
      httpClient: injectedClient,
    );

    if (!mounted) return;
    setState(() {
      _isSearchingPubDev = false;
      _pubSearchResult = result;
    });
  }

  Future<void> _handleAddPackage({
    required String name,
    required String versionConstraint,
    required bool isDev,
  }) async {
    final cleanName = name.trim().toLowerCase();
    if (!PubspecDependenciesService.validPackageNameRegex.hasMatch(cleanName)) {
      AppToast.error(
        context,
        'Nome de pacote inválido. Use snake_case (ex.: flutter_riverpod).',
      );
      return;
    }

    final ok = await PubspecDependenciesService.addOrUpdateDependency(
      projectRoot: widget.project.path,
      packageName: cleanName,
      versionConstraint: versionConstraint,
      isDev: isDev,
    );

    if (!mounted) return;
    if (ok) {
      _refreshAndSyncProject();
      AppToast.success(
        context,
        'Pacote "$cleanName" (${versionConstraint.isEmpty ? "any" : versionConstraint}) salvo em ${isDev ? "dev_dependencies" : "dependencies"}!',
      );
    } else {
      AppToast.error(
        context,
        'Não foi possível gravar "$cleanName" em pubspec.yaml.',
      );
    }
  }

  Future<void> _handleRemovePackage(PubspecDependencyEntry entry) async {
    final ok = await PubspecDependenciesService.removeDependency(
      projectRoot: widget.project.path,
      packageName: entry.name,
      isDev: entry.isDev,
    );
    if (!mounted) return;
    if (ok) {
      _refreshAndSyncProject();
      AppToast.info(context, 'Dependência "${entry.name}" removida do pubspec.yaml.');
    } else {
      AppToast.error(context, 'Não foi possível remover "${entry.name}".');
    }
  }

  Future<void> _handleEditDependencyVersion(PubspecDependencyEntry entry) async {
    final updatedVersion = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextDialog(
        title: 'Versão de ${entry.name}',
        labelText: 'Constraint (ex.: ^2.6.1, any)',
        initialValue: entry.constraint,
        confirmLabel: 'Salvar',
        monospace: true,
        autofocus: true,
      ),
    );

    if (updatedVersion == null || updatedVersion.isEmpty || !mounted) return;
    await _handleAddPackage(
      name: entry.name,
      versionConstraint: updatedVersion,
      isDev: entry.isDev,
    );
  }

  Future<void> _handleRunPubGet() async {
    if (_isRunningPubGet) return;
    setState(() => _isRunningPubGet = true);

    final runner = widget.pubGetRunner ?? PubspecDependenciesService.runPubGet;
    final res = await runner(widget.project.path);

    if (!mounted) return;
    setState(() {
      _isRunningPubGet = false;
      _reloadDiskSnapshots();
    });

    if (res.success) {
      AppToast.success(context, 'flutter pub get concluído com sucesso!');
    } else {
      AppToast.error(
        context,
        'Falha no flutter pub get: ${res.output.split('\n').first}',
      );
    }
  }

  Future<void> _handleToggleKnownPermission(
    NativePermissionDescriptor desc,
    bool enabled,
  ) async {
    final ok = await NativePermissionsService.setKnownPermissionEnabled(
      projectRoot: widget.project.path,
      descriptor: desc,
      enabled: enabled,
    );
    if (!mounted) return;
    if (ok) {
      _refreshAndSyncProject();
      AppToast.success(
        context,
        enabled
            ? 'Permissão "${desc.name}" adicionada aos arquivos nativos!'
            : 'Permissão "${desc.name}" removida dos arquivos nativos.',
      );
    } else {
      AppToast.error(
        context,
        'Nenhum AndroidManifest.xml / Info.plist gravável encontrado neste projeto.',
      );
    }
  }

  Future<void> _handleAddCustomPermission() async {
    final androidTag = NativePermissionsService.normalizeAndroidTag(
      _customAndroidPermController.text,
    );
    final iosKey = _customIosKeyController.text.trim();
    final iosReason = _customIosReasonController.text.trim();

    if (androidTag.isEmpty && iosKey.isEmpty) {
      AppToast.error(
        context,
        'Informe uma permissão Android (ex.: INTERNET) ou chave Info.plist iOS.',
      );
      return;
    }

    var changed = false;
    if (androidTag.isNotEmpty) {
      changed = await NativePermissionsService.addAndroidPermission(
            projectRoot: widget.project.path,
            permissionTag: androidTag,
          ) ||
          changed;
    }

    if (iosKey.isNotEmpty) {
      changed = await NativePermissionsService.setIosPermission(
            projectRoot: widget.project.path,
            iosKey: iosKey,
            reason: iosReason.isNotEmpty
                ? iosReason
                : 'Required permission for $iosKey.',
          ) ||
          changed;
    }

    if (!mounted) return;
    if (changed) {
      _customAndroidPermController.clear();
      _customIosKeyController.clear();
      _customIosReasonController.clear();
      _refreshAndSyncProject();
      AppToast.success(context, 'Permissão nativa adicionada ao projeto!');
    } else {
      AppToast.error(
        context,
        'Verifique se AndroidManifest.xml / Info.plist existem neste projeto.',
      );
    }
  }

  Future<void> _handleRemoveAndroidPermission(String tag) async {
    final ok = await NativePermissionsService.removeAndroidPermission(
      projectRoot: widget.project.path,
      permissionTag: tag,
    );
    if (!mounted) return;
    if (ok) {
      _refreshAndSyncProject();
      AppToast.info(context, 'Removida: $tag');
    } else {
      AppToast.error(context, 'Não foi possível remover $tag.');
    }
  }

  Future<void> _handleEditIosReason(String iosKey, String currentReason) async {
    final newReason = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextDialog(
        title: 'Descrição iOS ($iosKey)',
        labelText: 'Mensagem exibida ao usuário na App Store / iOS',
        initialValue: currentReason,
        confirmLabel: 'Salvar no Info.plist',
        maxLines: 3,
      ),
    );

    if (newReason == null || newReason.isEmpty || !mounted) return;
    final ok = await NativePermissionsService.setIosPermission(
      projectRoot: widget.project.path,
      iosKey: iosKey,
      reason: newReason,
    );
    if (!mounted) return;
    if (ok) {
      _refreshAndSyncProject();
      AppToast.success(context, 'Chave $iosKey atualizada em Info.plist!');
    }
  }

  Future<void> _handleRemoveIosPermission(String iosKey) async {
    final ok = await NativePermissionsService.removeIosPermission(
      projectRoot: widget.project.path,
      iosKey: iosKey,
    );
    if (!mounted) return;
    if (ok) {
      _refreshAndSyncProject();
      AppToast.info(context, 'Chave $iosKey removida do Info.plist.');
    }
  }

  Future<void> _openPackageUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('packages_permissions_unified_hub'),
      color: AppColors.background,
      child: Column(
        children: [
          _buildHubTopBanner(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 960;
                if (isWide) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 11,
                          child: _buildDependenciesColumn(),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 10,
                          child: _buildPermissionsColumn(),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 620,
                        child: _buildDependenciesColumn(),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 620,
                        child: _buildPermissionsColumn(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHubTopBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.extension_rounded,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Hub de Dependências & Permissões — ${widget.project.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusBadge(
                    label: 'pubspec.yaml',
                    isActive: _depsSnapshot.exists,
                  ),
                  _StatusBadge(
                    label: 'AndroidManifest.xml',
                    isActive: _permsSnapshot.hasAndroidManifest,
                  ),
                  _StatusBadge(
                    label: 'Info.plist',
                    isActive: _permsSnapshot.hasIosPlist,
                  ),
                  Text(
                    'Stack: ${widget.project.preset.name}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('hub_refresh_disk_button'),
                onPressed: _refreshAndSyncProject,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Recarregar', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
              ),
              ElevatedButton.icon(
                key: const ValueKey('hub_run_pub_get_button'),
                onPressed: _isRunningPubGet ? null : _handleRunPubGet,
                icon: _isRunningPubGet
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_done_rounded, size: 15),
                label: Text(
                  _isRunningPubGet ? 'Rodando pub get...' : 'Rodar flutter pub get',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDependenciesColumn() {
    final installedNames = _depsSnapshot.allPackageNames;
    final results = _pubSearchResult?.packages ?? const <PubDevPackageInfo>[];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Title Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2_rounded,
                  size: 16,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Dependências (pub.dev & pubspec.yaml)',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _CountChip(
                  label: '${_depsSnapshot.dependencies.length} deps',
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 6),
                _CountChip(
                  label: '${_depsSnapshot.devDependencies.length} dev',
                  color: AppColors.primary,
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // 1. Live pub.dev search panel
                _buildPubDevSearchBox(installedNames, results),
                const SizedBox(height: 14),

                // 2. Quick manual package add form (always available offline/custom)
                _buildManualDependencyForm(),
                const SizedBox(height: 14),

                // 3. Installed dependencies from real pubspec.yaml
                _buildInstalledDependenciesSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPubDevSearchBox(
    Set<String> installedNames,
    List<PubDevPackageInfo> results,
  ) {
    const quickQueries = [
      ('State', 'riverpod'),
      ('HTTP', 'dio'),
      ('Storage', 'shared_preferences'),
      ('Mídia', 'image_picker'),
      ('Rotas', 'go_router'),
      ('Permissões', 'permission_handler'),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.public_rounded,
                size: 14,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Buscar pacotes bem avaliados direto no pub.dev',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_pubSearchResult?.fromOfflineFallback == true)
                const Text(
                  'Modo Offline Curado',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('pubdev_search_input'),
                  controller: _pubSearchController,
                  onSubmitted: _performPubDevSearch,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Ex.: dio, riverpod, image_picker, sqflite...',
                    hintStyle: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                key: const ValueKey('pubdev_search_button'),
                onPressed: _isSearchingPubDev
                    ? null
                    : () => _performPubDevSearch(_pubSearchController.text),
                icon: _isSearchingPubDev
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search_rounded, size: 15),
                label: const Text('Buscar', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                key: const ValueKey('pubdev_high_rated_filter'),
                label: const Text(
                  'Bem avaliadas (120+ pts)',
                  style: TextStyle(fontSize: 10.5),
                ),
                selected: _highRatedOnly,
                selectedColor: AppColors.success.withOpacity(0.18),
                checkmarkColor: AppColors.success,
                labelStyle: TextStyle(
                  color: _highRatedOnly
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color: _highRatedOnly
                      ? AppColors.success.withOpacity(0.5)
                      : AppColors.border,
                ),
                onSelected: (v) {
                  setState(() => _highRatedOnly = v);
                  _performPubDevSearch(_pubSearchController.text);
                },
              ),
              FilterChip(
                key: const ValueKey('pubdev_favorites_filter'),
                label: const Text(
                  'Flutter Favorite ★',
                  style: TextStyle(fontSize: 10.5),
                ),
                selected: _favoritesOnly,
                selectedColor: AppColors.warning.withOpacity(0.18),
                checkmarkColor: AppColors.warning,
                labelStyle: TextStyle(
                  color: _favoritesOnly
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color: _favoritesOnly
                      ? AppColors.warning.withOpacity(0.5)
                      : AppColors.border,
                ),
                onSelected: (v) {
                  setState(() => _favoritesOnly = v);
                  _performPubDevSearch(_pubSearchController.text);
                },
              ),
              DropdownButton<PubDevSort>(
                value: _sort,
                dropdownColor: AppColors.surfaceCard,
                underline: const SizedBox.shrink(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
                items: PubDevSort.values
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text('Ordenar: ${s.label}'),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _sort = val);
                  _performPubDevSearch(_pubSearchController.text);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: quickQueries
                .map(
                  (q) => ActionChip(
                    label: Text(q.$1, style: const TextStyle(fontSize: 10)),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    labelStyle: const TextStyle(color: AppColors.secondary),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _pubSearchController.text = q.$2;
                      _performPubDevSearch(q.$2);
                    },
                  ),
                )
                .toList(),
          ),
          if (_pubSearchResult?.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _pubSearchResult!.errorMessage!,
              style: const TextStyle(color: AppColors.warning, fontSize: 10.5),
            ),
          ],
          const SizedBox(height: 10),
          if (_isSearchingPubDev && results.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum pacote encontrado para essa busca.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            )
          else
            Column(
              children: [
                for (final pkg in results.take(8)) ...[
                  _buildPubDevResultRow(pkg, installedNames.contains(pkg.name)),
                  const SizedBox(height: 6),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPubDevResultRow(PubDevPackageInfo pkg, bool isInstalled) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isInstalled
              ? AppColors.success.withOpacity(0.4)
              : AppColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      pkg.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (pkg.latestVersion.isNotEmpty)
                      Text(
                        '^${pkg.latestVersion}',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    _CountChip(
                      label: '${pkg.grantedPoints}/${pkg.maxPoints} pts',
                      color: pkg.isHighRated
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    _CountChip(
                      label: '♥ ${pkg.formattedLikes}',
                      color: AppColors.primary,
                    ),
                    if (pkg.isFlutterFavorite)
                      _CountChip(
                        label: '★ Favorite',
                        color: AppColors.warning,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Abrir no pub.dev',
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                color: AppColors.textMuted,
                visualDensity: VisualDensity.compact,
                onPressed: () => _openPackageUrl(pkg.pubDevUrl),
              ),
            ],
          ),
          if (pkg.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              pkg.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (pkg.publisher != null)
                Expanded(
                  child: Text(
                    'Publisher: ${pkg.publisher}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                )
              else
                const Spacer(),
              OutlinedButton(
                key: ValueKey('pubdev_add_dev_${pkg.name}'),
                onPressed: () => _handleAddPackage(
                  name: pkg.name,
                  versionConstraint: pkg.versionConstraint,
                  isDev: true,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('+ Dev', style: TextStyle(fontSize: 10.5)),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                key: ValueKey('pubdev_add_${pkg.name}'),
                onPressed: () => _handleAddPackage(
                  name: pkg.name,
                  versionConstraint: pkg.versionConstraint,
                  isDev: false,
                ),
                icon: Icon(
                  isInstalled ? Icons.sync_rounded : Icons.add_rounded,
                  size: 13,
                ),
                label: Text(
                  isInstalled ? 'Atualizar' : 'Adicionar',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isInstalled ? AppColors.surfaceHover : AppColors.success,
                  foregroundColor:
                      isInstalled ? AppColors.success : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualDependencyForm() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inclusão Manual Rápida (Offline ou Específica)',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey('manual_pkg_name_input'),
                  controller: _manualPkgNameController,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'nome_do_pacote',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('manual_pkg_version_input'),
                  controller: _manualPkgVersionController,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '^1.0.0 ou any',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('dev', style: TextStyle(fontSize: 10.5)),
                selected: _manualIsDev,
                onSelected: (v) => setState(() => _manualIsDev = v),
                selectedColor: AppColors.primary.withOpacity(0.2),
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.border),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                key: const ValueKey('manual_pkg_add_button'),
                onPressed: () async {
                  await _handleAddPackage(
                    name: _manualPkgNameController.text,
                    versionConstraint: _manualPkgVersionController.text.isEmpty
                        ? 'any'
                        : _manualPkgVersionController.text,
                    isDev: _manualIsDev,
                  );
                  if (mounted) {
                    _manualPkgNameController.clear();
                    _manualPkgVersionController.clear();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                child: const Text('Incluir', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledDependenciesSection() {
    if (_depsSnapshot.errorMessage != null) {
      return Text(
        _depsSnapshot.errorMessage!,
        style: const TextStyle(color: AppColors.warning, fontSize: 12),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dependências Atuais no pubspec.yaml',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (_depsSnapshot.dependencies.isEmpty &&
              _depsSnapshot.devDependencies.isEmpty)
            const Text(
              'Nenhuma dependência declarada no momento.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          for (final dep in _depsSnapshot.dependencies)
            _buildInstalledDepTile(dep),
          if (_depsSnapshot.devDependencies.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'dev_dependencies',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            for (final dep in _depsSnapshot.devDependencies)
              _buildInstalledDepTile(dep),
          ],
        ],
      ),
    );
  }

  Widget _buildInstalledDepTile(PubspecDependencyEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(
            entry.isDev ? Icons.build_circle_outlined : Icons.extension_rounded,
            size: 13,
            color: entry.isDev ? AppColors.primary : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            entry.constraint,
            style: const TextStyle(
              color: AppColors.secondary,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          if (entry.isEditableVersion && entry.isRemovable)
            IconButton(
              key: ValueKey('edit_dep_${entry.name}'),
              tooltip: 'Alterar versão',
              icon: const Icon(Icons.edit_rounded, size: 13),
              color: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
              onPressed: () => _handleEditDependencyVersion(entry),
            ),
          if (entry.isRemovable)
            IconButton(
              key: ValueKey('remove_dep_${entry.name}'),
              tooltip: 'Remover do pubspec.yaml',
              icon: const Icon(Icons.delete_outline_rounded, size: 14),
              color: AppColors.danger,
              visualDensity: VisualDensity.compact,
              onPressed: () => _handleRemovePackage(entry),
            ),
        ],
      ),
    );
  }

  Widget _buildPermissionsColumn() {
    final activeCount = _permsSnapshot.androidPermissions.length;
    final iosCount = _permsSnapshot.iosUsageDescriptions.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.security_rounded,
                  size: 16,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Permissões Nativas (Android & iOS)',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _CountChip(
                  label: '$activeCount Android',
                  color: AppColors.success,
                ),
                const SizedBox(width: 6),
                _CountChip(
                  label: '$iosCount iOS',
                  color: AppColors.secondary,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (_permsSnapshot.errorMessage != null) ...[
                  Text(
                    _permsSnapshot.errorMessage!,
                    style: const TextStyle(color: AppColors.warning, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                ],
                _buildCommonPermissionsToggleSection(),
                const SizedBox(height: 14),
                _buildCustomPermissionForm(),
                const SizedBox(height: 14),
                _buildActiveManifestPermissionsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommonPermissionsToggleSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ativar / Remover Permissões Populares',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Edita AndroidManifest.xml e ios/Runner/Info.plist com segurança sem corromper XML.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          for (final desc in NativePermissionsService.commonPermissions) ...[
            _buildPermissionToggleCard(desc),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionToggleCard(NativePermissionDescriptor desc) {
    final isEnabled = _permsSnapshot.hasPermission(desc);
    final iosReason = desc.iosKey != null
        ? _permsSnapshot.iosUsageDescriptions[desc.iosKey!]
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEnabled
              ? AppColors.success.withOpacity(0.45)
              : AppColors.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: (isEnabled ? AppColors.success : AppColors.textMuted)
                  .withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              desc.icon,
              size: 15,
              color: isEnabled ? AppColors.success : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  desc.androidTag,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (desc.iosKey != null && _permsSnapshot.hasIosPlist && isEnabled)
            IconButton(
              tooltip: 'Editar descrição iOS (${desc.iosKey})',
              icon: const Icon(Icons.edit_note_rounded, size: 16),
              color: AppColors.secondary,
              visualDensity: VisualDensity.compact,
              onPressed: () => _handleEditIosReason(
                desc.iosKey!,
                iosReason ?? desc.iosDefaultReason ?? '',
              ),
            ),
          Switch.adaptive(
            key: ValueKey('perm_toggle_${desc.id}'),
            value: isEnabled,
            activeColor: AppColors.success,
            onChanged: (!_permsSnapshot.hasAndroidManifest &&
                    !_permsSnapshot.hasIosPlist)
                ? null
                : (v) => _handleToggleKnownPermission(desc, v),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomPermissionForm() {
    const quickTags = [
      'WAKE_LOCK',
      'ACCESS_NETWORK_STATE',
      'VIBRATE',
      'MANAGE_EXTERNAL_STORAGE',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adicionar Permissão Personalizada',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('custom_perm_android_input'),
            controller: _customAndroidPermController,
            style: const TextStyle(
              color: AppColors.secondary,
              fontFamily: 'monospace',
              fontSize: 11.5,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Ex.: android.permission.WAKE_LOCK ou VIBRATE',
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: quickTags
                .map(
                  (t) => ActionChip(
                    label: Text(t, style: const TextStyle(fontSize: 9.5)),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _customAndroidPermController.text =
                          'android.permission.$t';
                    },
                  ),
                )
                .toList(),
          ),
          if (_permsSnapshot.hasIosPlist) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('custom_perm_ios_key_input'),
                    controller: _customIosKeyController,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'iOS Info.plist Key (opcional)',
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('custom_perm_ios_reason_input'),
                    controller: _customIosReasonController,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Motivo para usuário (opcional)',
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const ValueKey('custom_perm_add_button'),
              onPressed: _handleAddCustomPermission,
              icon: const Icon(Icons.add_moderator_rounded, size: 14),
              label: const Text(
                'Adicionar Permissão',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveManifestPermissionsList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tags Reais Declaradas no Projeto',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (_permsSnapshot.androidPermissions.isEmpty &&
              _permsSnapshot.iosUsageDescriptions.isEmpty)
            const Text(
              'Nenhuma permissão nativa declarada no AndroidManifest.xml ou Info.plist.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          for (final tag in _permsSnapshot.androidPermissions)
            Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.android_rounded,
                    size: 14,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      tag,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('remove_android_perm_$tag'),
                    tooltip: 'Remover do AndroidManifest.xml',
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    color: AppColors.danger,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _handleRemoveAndroidPermission(tag),
                  ),
                ],
              ),
            ),
          for (final entry in _permsSnapshot.iosUsageDescriptions.entries)
            Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_iphone_rounded,
                    size: 14,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          entry.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar razão iOS',
                    icon: const Icon(Icons.edit_rounded, size: 13),
                    color: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _handleEditIosReason(entry.key, entry.value),
                  ),
                  IconButton(
                    key: ValueKey('remove_ios_perm_${entry.key}'),
                    tooltip: 'Remover do Info.plist',
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    color: AppColors.danger,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _handleRemoveIosPermission(entry.key),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool isActive;

  const _StatusBadge({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle_rounded : Icons.remove_circle_outline,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;

  const _CountChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _EditTextDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String initialValue;
  final String confirmLabel;
  final bool monospace;
  final bool autofocus;
  final int maxLines;

  const _EditTextDialog({
    required this.title,
    required this.labelText,
    required this.initialValue,
    required this.confirmLabel,
    this.monospace = false,
    this.autofocus = false,
    this.maxLines = 1,
  });

  @override
  State<_EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<_EditTextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.backgroundSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5),
      ),
      content: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        maxLines: widget.maxLines,
        style: TextStyle(
          fontFamily: widget.monospace ? 'monospace' : null,
          fontSize: 12.5,
          color: widget.monospace ? AppColors.secondary : AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          labelText: widget.labelText,
          labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          filled: true,
          fillColor: AppColors.surface,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
