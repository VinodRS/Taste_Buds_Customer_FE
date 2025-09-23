import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ResetPasswordScreen extends StatefulWidget {
  final String token; // Token from email

  const ResetPasswordScreen({super.key, required this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  String message = '';

  Future<void> resetPassword() async {
    final password = passwordController.text;

    if (password.isEmpty) {
      setState(() => message = "Password cannot be empty.");
      return;
    }

    setState(() {
      isLoading = true;
      message = '';
    });

    try {
      final response = await http.post(
        Uri.parse("http://192.168.86.37:8601/api/customer/reset-password"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': widget.token, 'password': password}),
      );

      if (response.statusCode == 200) {
        setState(() => message = "Password reset successful!");
      } else {
        setState(() => message = "Invalid or expired token.");
      }
    } catch (_) {
      setState(() => message = "Something went wrong.");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset Password")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("Enter your new password."),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "New Password"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: isLoading ? null : resetPassword,
              child: isLoading
                  ? const CircularProgressIndicator()
                  : const Text("Reset Password"),
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(message, style: const TextStyle(color: Colors.green)),
              ),
          ],
        ),
      ),
    );
  }
}
