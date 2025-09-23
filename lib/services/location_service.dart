import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Timer? _locationTimer;

/// Starts background location updates every 30 seconds and sends them to the server.
void startLocationUpdates() async {
  _locationTimer?.cancel(); // avoid duplicates

  _locationTimer = Timer.periodic(Duration(seconds: 30), (_) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token == null) return;

    final position = await getCurrentLocation();
    if (position == null) return;

    final response = await http.post(
      Uri.parse('http://192.168.86.37:8601/api/customer/location-update'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'latitude': position.latitude,
        'longitude': position.longitude,
      }),
    );

    if (response.statusCode == 200) {
      print("📍 Location sent: ${position.latitude}, ${position.longitude}");
    } else {
      print("❌ Failed to send location: ${response.statusCode}");
    }
  });
}

/// Gets the current location with permission handling.
/// Returns `Position` or `null` if permission is denied or services are off.
Future<Position?> getCurrentLocation() async {
  bool serviceEnabled;
  LocationPermission permission;

  // Check if location services are enabled
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    print("⚠️ Location services are disabled.");
    return null;
  }

  // Check and request permissions
  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      print("🚫 Location permission denied.");
      return null;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    print("⛔ Location permissions are permanently denied.");
    return null;
  }

  // Get current position
  return await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
}
