import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/project_config.dart';

enum WizardStep {
  project(title: 'Project Info', subtitle: 'Name, org & output path'),
  preset(title: 'Stack Preset', subtitle: 'Architectural foundation'),
  navigation(title: 'Navigation Style', subtitle: 'Tabs, drawer or adaptive'),
  theme(title: 'Theme & Contrast', subtitle: 'WCAG auto-contrast color engine'),
  permissions(title: 'Smart Permissions', subtitle: 'Automated native configs'),
  native(title: 'Native Target', subtitle: 'Android & iOS build properties');

  final String title;
  final String subtitle;
  const WizardStep({required this.title, required this.subtitle});
}

class WizardState {
  final WizardStep currentStep;
  final ProjectConfig config;
  final bool isGenerating;
  final List<String> logs;
  final bool? isSuccess;
  final String? errorMessage;

  const WizardState({
    this.currentStep = WizardStep.project,
    this.config = const ProjectConfig(),
    this.isGenerating = false,
    this.logs = const [],
    this.isSuccess,
    this.errorMessage,
  });

  WizardState copyWith({
    WizardStep? currentStep,
    ProjectConfig? config,
    bool? isGenerating,
    List<String>? logs,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return WizardState(
      currentStep: currentStep ?? this.currentStep,
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

  void setStep(WizardStep step) {
    state = state.copyWith(currentStep: step);
  }

  void nextStep() {
    final nextIndex = state.currentStep.index + 1;
    if (nextIndex < WizardStep.values.length) {
      state = state.copyWith(currentStep: WizardStep.values[nextIndex]);
    }
  }

  void previousStep() {
    final prevIndex = state.currentStep.index - 1;
    if (prevIndex >= 0) {
      state = state.copyWith(currentStep: WizardStep.values[prevIndex]);
    }
  }

  void updateConfig(ProjectConfig Function(ProjectConfig current) updater) {
    state = state.copyWith(config: updater(state.config));
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
