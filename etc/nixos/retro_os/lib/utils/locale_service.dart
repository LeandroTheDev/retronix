import 'package:flutter/foundation.dart';
import 'settings_service.dart';

class LocaleService extends ChangeNotifier {
  LocaleService._();
  static final instance = LocaleService._();

  String _locale = 'en_us';
  String get locale => _locale;

  Future<void> load() async {
    _locale = await SettingsService.instance.language();
  }

  Future<void> setLocale(String locale) async {
    if (_locale == locale) return;
    _locale = locale;
    await SettingsService.instance.setLanguage(locale);
    notifyListeners();
  }

  void toggle() {
    setLocale(_locale == 'en_us' ? 'pt_br' : 'en_us');
  }
}
