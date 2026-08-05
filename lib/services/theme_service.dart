import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  static const _pinkKey = 'pink_theme_enabled';
  bool _isPink = true;

  bool get isPink => _isPink;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isPink = prefs.getBool(_pinkKey) ?? true;
  }

  Future<void> setPink(bool value) async {
    if (_isPink == value) return;
    _isPink = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pinkKey, value);
  }
}
