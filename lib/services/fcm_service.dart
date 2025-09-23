// lib/services/fcm_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<void> registerFcmToken() async {
  final fcm = FirebaseMessaging.instance;
  final token = await fcm.getToken();

  if (token != null) {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');

    final response = await http.post(
      Uri.parse("http://192.168.86.37:8601/api/customer/register-fcm-token"), // Update as needed
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'token': token}),
    );

    if (response.statusCode == 200) {
      print("✅ FCM token registered successfully.");
    } else {
      print("❌ Failed to register FCM token: ${response.body}");
    }
  } else {
    print("❌ Failed to retrieve FCM token.");
  }
}
