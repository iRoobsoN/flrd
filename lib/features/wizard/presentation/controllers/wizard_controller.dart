import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/project_config.dart';

enum WizardStep {
  project(
    title: 'Identidade do App',
    subtitle: 'Nome, pacote e pasta de destino',
  ),
  preset(
    title: 'Preset de Arquitetura',
    subtitle: 'Modelo técnico e exemplos de apps',
  ),
  navigation(
    title: 'Estilo de Navegação',
    subtitle: 'Abas, menu lateral ou adaptativo',
  ),
  theme(
    title: 'Cores & Contraste',
    subtitle: 'Paleta Material 3 e legibilidade',
  ),
  permissions(
    title: 'Permissões Nativas',
    subtitle: 'Câmera, GPS, galeria e alertas',
  ),
  native(
    title: 'Android, iOS & Revisão',
    subtitle: 'Versões mínimas e conferência final',
  );

  final String title;
  final String subtitle;
  const WizardStep({required this.title, required this.subtitle});
}

class WizardState {
  final WizardStep currentStep;
  final Set<WizardStep> completedSteps;
  final ProjectConfig config;
  final bool isGenerating;
  final List<String> logs;
  final bool? isSuccess;
  final String? errorMessage;

  const WizardState({
    this.currentStep = WizardStep.project,
    this.completedSteps = const {},
    this.config = const ProjectConfig(),
    this.isGenerating = false,
    this.logs = const [],
    this.isSuccess,
    this.errorMessage,
  });

  /// Highest sequential step index unlocked after completing previous steps.
  int get maxUnlockedStepIndex {
    var unlocked = 0;
    while (unlocked < WizardStep.values.length - 1 &&
        completedSteps.contains(WizardStep.values[unlocked]) &&
        validateStep(WizardStep.values[unlocked]) == null) {
      unlocked++;
    }
    return unlocked;
  }

  bool isStepUnlocked(WizardStep step) => step.index <= maxUnlockedStepIndex;

  bool isStepCompleted(WizardStep step) =>
      completedSteps.contains(step) && validateStep(step) == null;

  bool get hasCompletedAllSteps =>
      WizardStep.values.every(completedSteps.contains);

  WizardStep get firstIncompleteStep {
    for (final step in WizardStep.values) {
      if (!isStepCompleted(step)) return step;
    }
    return WizardStep.values.last;
  }

  int get completedCount {
    var count = 0;
    for (final step in WizardStep.values) {
      if (isStepCompleted(step)) count++;
    }
    return count;
  }

  String? validateStep(WizardStep step) {
    if (step == WizardStep.project || step == WizardStep.native) {
      final nameError = ProjectNameValidator.validate(config.projectName);
      if (nameError != null) return nameError;

      final orgError = OrgIdValidator.validate(config.orgId);
      if (orgError != null) return orgError;

      if (config.outputPath.trim().isEmpty) {
        return 'Selecione uma pasta de destino para criar o projeto.';
      }
    }
    return null;
  }

  bool get canGenerateProject =>
      hasCompletedAllSteps && validateStep(WizardStep.project) == null;

  WizardState copyWith({
    WizardStep? currentStep,
    Set<WizardStep>? completedSteps,
    ProjectConfig? config,
    bool? isGenerating,
    List<String>? logs,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return WizardState(
      currentStep: currentStep ?? this.currentStep,
      completedSteps: completedSteps ?? this.completedSteps,
      config: config ?? this.config,
      isGenerating: isGenerating ?? this.isGenerating,
      logs: logs ?? this.logs,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class WizardNotifier extends StateNotifier<WizardState> {
  WizardNotifier() : super(const WizardState());

  void resetWizard({ProjectConfig? initialConfig}) {
    state = WizardState(
      currentStep: WizardStep.project,
      completedSteps: const {},
      config: initialConfig ?? const ProjectConfig(),
    );
  }

  bool setStep(WizardStep step) {
    if (!state.isStepUnlocked(step)) {
      return false;
    }
    state = state.copyWith(currentStep: step);
    return true;
  }

  /// Validates the current step, marks it completed, and advances sequentially.
  /// Returns a validation error message if the current step is incomplete/invalid.
  String? nextStep() {
    final error = state.validateStep(state.currentStep);
    if (error != null) return error;

    final updatedCompleted = <WizardStep>{
      ...state.completedSteps,
      state.currentStep,
    };

    final nextIndex = state.currentStep.index + 1;
    if (nextIndex < WizardStep.values.length) {
      final next = WizardStep.values[nextIndex];
      if (nextIndex == WizardStep.values.length - 1) {
        updatedCompleted.add(next);
      }
      state = state.copyWith(
        currentStep: next,
        completedSteps: updatedCompleted,
      );
    } else {
      state = state.copyWith(completedSteps: updatedCompleted);
    }
    return null;
  }

  void previousStep() {
    final prevIndex = state.currentStep.index - 1;
    if (prevIndex >= 0) {
      state = state.copyWith(currentStep: WizardStep.values[prevIndex]);
    }
  }

  void updateConfig(ProjectConfig Function(ProjectConfig current) updater) {
    final nextConfig = updater(state.config);
    state = state.copyWith(config: nextConfig);
  }

  void addLog(String log) {
    state = state.copyWith(logs: [...state.logs, log]);
  }

  void resetGeneration() {
    state = state.copyWith(
      isGenerating: false,
      logs: [],
      isSuccess: null,
      errorMessage: null,
    );
  }
}

final wizardProvider = StateNotifierProvider<WizardNotifier, WizardState>((ref) {
  return WizardNotifier();
});
