import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/template_submission.dart';
import '../../providers/marketplace_provider.dart';
import '../../services/template_guardian_service.dart';

class PublishTemplateDialog extends ConsumerStatefulWidget {
  final String? initialProjectPath;

  const PublishTemplateDialog({
    super.key,
    this.initialProjectPath,
  });

  static Future<void> show(BuildContext context, {String? projectPath}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => PublishTemplateDialog(initialProjectPath: projectPath),
    );
  }

  @override
  ConsumerState<PublishTemplateDialog> createState() => _PublishTemplateDialogState();
}

class _PublishTemplateDialogState extends ConsumerState<PublishTemplateDialog> {
  final _guardian = TemplateGuardianService();

  final _titleController = TextEditingController();
  final _authorController = TextEditingController(text: 'Robson David');
  final _githubController = TextEditingController(text: 'iRoobsoN');
  final _payoutController = TextEditingController(text: 'robson.dv14@gmail.com');
  final _priceController = TextEditingController(text: '29');
  final _descController = TextEditingController();
  late final TextEditingController _pathController;

  TemplateTier _selectedTier = TemplateTier.starterKit;
  bool _isAuditing = false;
  SubmissionValidationResult? _auditResult;
  bool _manifestGenerated = false;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(
      text: widget.initialProjectPath ?? Directory.current.path,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _githubController.dispose();
    _payoutController.dispose();
    _priceController.dispose();
    _descController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  double get _currentPrice => double.tryParse(_priceController.text) ?? 0.0;
  bool get _isBelowFloor => _currentPrice < _selectedTier.minimumPriceUsd;

  Future<void> _runAudit() async {
    setState(() {
      _isAuditing = true;
      _auditResult = null;
      _manifestGenerated = false;
    });

    final submission = TemplateSubmissionData(
      title: _titleController.text.trim().isEmpty ? 'Meu Template' : _titleController.text.trim(),
      authorName: _authorController.text.trim(),
      githubHandle: _githubController.text.trim(),
      payoutAccount: _payoutController.text.trim(),
      tier: _selectedTier,
      priceUsd: _currentPrice,
      description: _descController.text.trim(),
      projectPath: _pathController.text.trim(),
    );

    final knownFingerprints = ref.read(marketplaceKnownFingerprintsProvider);
    final projectDir = Directory(submission.projectPath);

    final result = await _guardian.validateSubmission(
      submission: submission,
      knownTemplates: knownFingerprints,
      projectDir: projectDir,
    );

    setState(() {
      _isAuditing = false;
      _auditResult = result;
    });
  }

  Future<void> _generatePackage() async {
    final submission = TemplateSubmissionData(
      title: _titleController.text.trim().isEmpty ? 'Meu Template' : _titleController.text.trim(),
      authorName: _authorController.text.trim(),
      githubHandle: _githubController.text.trim(),
      payoutAccount: _payoutController.text.trim(),
      tier: _selectedTier,
      priceUsd: _currentPrice,
      description: _descController.text.trim(),
      projectPath: _pathController.text.trim(),
    );

    final projectDir = Directory(submission.projectPath);
    final fingerprint = await _guardian.generateFingerprint(projectDir, templateId: submission.title);

    final manifestData = _guardian.generateSignedManifest(
      submission: submission,
      fingerprint: fingerprint,
    );

    // Save manifest to project directory if it exists
    if (await projectDir.exists()) {
      final flrdDir = Directory('${projectDir.path}/.flrd');
      if (!await flrdDir.exists()) {
        await flrdDir.create(recursive: true);
      }
      final manifestFile = File('${flrdDir.path}/manifest.json');
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifestData),
        flush: true,
      );
    }

    setState(() {
      _manifestGenerated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 820,
        constraints: const BoxConstraints(maxHeight: 780),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(context),
            const Divider(color: AppColors.border, height: 1),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPolicyBanner(),
                    const SizedBox(height: 20),

                    // Inputs Grid
                    _buildFormInputs(),
                    const SizedBox(height: 20),

                    // Price & Floor Section
                    _buildPricingSection(),
                    const SizedBox(height: 24),

                    // Audit Trigger & Results
                    _buildAuditSection(),
                  ],
                ),
              ),
            ),

            // Footer
            const Divider(color: AppColors.border, height: 1),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.secondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Publicar Template no Marketplace FLRD',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Curadoria oficial com piso de preço anti-prostituição e verificação estrutural anti-plágio.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Compromisso de Valor: Para proteger o ecossistema, os templates possuem preços mínimos por categoria e auditoria de AST para barrar clones com alteração trivial.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _titleController,
                label: 'Título Comercial do Template',
                hint: 'Ex: NovaBank FinTech Pro',
                icon: Icons.title_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _pathController,
                label: 'Pasta Local do Projeto',
                hint: 'c:/meus_projetos/meu_app',
                icon: Icons.folder_open_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _authorController,
                label: 'Nome do Autor / Criador',
                hint: 'Ex: Robson David',
                icon: Icons.person_outline_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _githubController,
                label: 'GitHub Handle',
                hint: 'Ex: iRoobsoN',
                icon: Icons.code_rounded,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _payoutController,
                label: 'Conta de Recebimento (Pix / PayPal)',
                hint: 'seu-email@gmail.com',
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPricingSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isBelowFloor ? AppColors.danger : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Categoria & Regra de Piso de Preço',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Tier Selectors
          Row(
            children: TemplateTier.values.map((tier) {
              final isSelected = _selectedTier == tier;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedTier = tier;
                        if (_currentPrice < tier.minimumPriceUsd) {
                          _priceController.text = tier.minimumPriceUsd.toStringAsFixed(0);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withOpacity(0.15)
                            : AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.borderSubtle,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tier.label,
                            style: TextStyle(
                              color: isSelected ? AppColors.primary : AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Piso: \$${tier.minimumPriceUsd.toStringAsFixed(0)} USD',
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Price Input and Split Calculator
          Row(
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Preço Pretendido (\$ USD)',
                    prefixText: '\$ ',
                    labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    filled: true,
                    fillColor: AppColors.surfaceCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Seu Repasse (75%)',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          Text(
                            '\$${(_currentPrice * 0.75).toStringAsFixed(2)} USD',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Taxa FLRD (25%)',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          Text(
                            '\$${(_currentPrice * 0.25).toStringAsFixed(2)} USD',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Piso Exigido',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          Text(
                            '\$${_selectedTier.minimumPriceUsd.toStringAsFixed(0)} USD',
                            style: TextStyle(
                              color: _isBelowFloor ? AppColors.danger : AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (_isBelowFloor) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.danger.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Preço abaixo do piso (\$${_selectedTier.minimumPriceUsd.toStringAsFixed(0)} USD). Ajuste o valor para prosseguir com a submissão.',
                      style: const TextStyle(color: AppColors.danger, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Auditoria de Segurança & Anti-Plágio',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isAuditing ? null : _runAudit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _isAuditing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.security_rounded, size: 16),
              label: Text(_isAuditing ? 'Auditando...' : 'Executar Auditoria'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_auditResult != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _auditResult!.isValid
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _auditResult!.isValid ? AppColors.success : AppColors.danger,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _auditResult!.isValid
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: _auditResult!.isValid ? AppColors.success : AppColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _auditResult!.isValid
                          ? 'Auditoria Aprovada com Sucesso!'
                          : 'Pendências Encontradas na Auditoria',
                      style: TextStyle(
                        color: _auditResult!.isValid ? AppColors.success : AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildAuditCheckRow(
                  label: 'Piso de Preço Respeitado',
                  passed: _auditResult!.priceFloorMet,
                ),
                _buildAuditCheckRow(
                  label: 'Segurança & Ausência de Chaves Privadas',
                  passed: _auditResult!.securityPassed,
                ),
                _buildAuditCheckRow(
                  label: 'Originalidade & Anti-Plágio (< 70% similaridade)',
                  passed: _auditResult!.originalityPassed,
                  extra: 'Similaridade máxima: ${(_auditResult!.similarityScore * 100).toStringAsFixed(1)}%',
                ),

                if (_auditResult!.errors.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(color: AppColors.borderSubtle),
                  ..._auditResult!.errors.map(
                    (err) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• $err',
                        style: const TextStyle(color: AppColors.danger, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: const Center(
              child: Text(
                'Clique em "Executar Auditoria" para validar conformidade com as regras do marketplace.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          ),
        ],

        if (_manifestGenerated) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Manifesto de titularidade assinado gerado em .flrd/manifest.json! Pronto para empacotamento.',
                    style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAuditCheckRow({required String label, required bool passed, String? extra}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_rounded : Icons.close_rounded,
            color: passed ? AppColors.success : AppColors.danger,
            size: 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: passed ? AppColors.textPrimary : AppColors.danger,
                fontSize: 12,
              ),
            ),
          ),
          if (extra != null)
            Text(
              extra,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 16, color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final canGenerate = _auditResult != null && _auditResult!.isValid && !_isBelowFloor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: canGenerate ? _generatePackage : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.rocket_launch_rounded, size: 16),
            label: const Text(
              'Gerar Manifesto & Empacotar (.flrdpkg)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
