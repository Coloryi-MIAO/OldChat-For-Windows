import 'package:shared_preferences/shared_preferences.dart';

class AISettings {
  final String apiKey;
  final String baseUrl;
  final String model;

  const AISettings({this.apiKey = '', this.baseUrl = '', this.model = ''});

  bool get isConfigured => apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty;
}

class AISettingsService {
  static const _apiKey = 'ai_personal_api_key';
  static const _baseUrl = 'ai_personal_base_url';
  static const _model = 'ai_personal_model';

  static Future<AISettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AISettings(
      apiKey: prefs.getString(_apiKey) ?? '',
      baseUrl: prefs.getString(_baseUrl) ?? '',
      model: prefs.getString(_model) ?? '',
    );
  }

  static Future<void> save({required String apiKey, required String baseUrl, String model = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKey, apiKey.trim());
    await prefs.setString(_baseUrl, baseUrl.trim());
    await prefs.setString(_model, model.trim());
  }
}
