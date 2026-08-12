import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  static const _pinkKey = 'pink_theme_enabled';
  static const _fontKey = 'app_font_family';
  bool _isPink = true;
  String _fontFamily = 'HarmonyOS Sans SC';

  bool get isPink => _isPink;
  String get fontFamily => _fontFamily;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isPink = prefs.getBool(_pinkKey) ?? true;
    final saved = prefs.getString(_fontKey);
    _fontFamily = saved == 'Microsoft YaHei' ? saved! : 'HarmonyOS Sans SC';
  }

  Future<void> setFontFamily(String value) async {
    if (value != 'Microsoft YaHei' && value != 'HarmonyOS Sans SC') return;
    if (_fontFamily == value) return;
    _fontFamily = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontKey, value);
  }

  Future<void> setPink(bool value) async {
    if (_isPink == value) return;
    _isPink = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pinkKey, value);
  }
}
