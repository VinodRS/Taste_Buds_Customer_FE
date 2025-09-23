import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<String?> getValidAccessToken() async {
  final prefs = await SharedPreferences.getInstance();
  final refreshToken = prefs.getString('refresh_token');

  if (refreshToken == null) return null;

  final response = await http.post(
    Uri.parse('http://192.168.86.37:8601/api/token/refresh/'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'refresh': refreshToken}),
  );

  if (response.statusCode == 200) {
    final newAccess = jsonDecode(response.body)['access'];
    prefs.setString('access_token', newAccess);
    return newAccess;
  }

  return null;
}
