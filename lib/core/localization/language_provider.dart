import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_strings.dart';

class LanguageNotifier extends StateNotifier<AppLanguage> {
  LanguageNotifier() : super(AppLanguage.en);

  void setLanguage(AppLanguage language) {
    state = language;
  }
}

final appLanguageProvider =
    StateNotifierProvider<LanguageNotifier, AppLanguage>((ref) {
      return LanguageNotifier();
    });

final appStringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(appLanguageProvider);
  return AppStrings(lang);
});
