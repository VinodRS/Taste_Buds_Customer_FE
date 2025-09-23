import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController emailController = TextEditingController();
  String message = '';
  bool isLoading = false;

  Future<void> sendResetRequest() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() => message = "Please enter your email.");
      return;
    }

    setState(() {
      isLoading = true;
      message = '';
    });

    try {
      final response = await http.post(
        Uri.parse("http://192.168.86.37:8601/api/customer/request-password-reset"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        setState(() {
          message = "Reset link sent! Check your email.";
        });
      } else {
        setState(() {
          message = "Failed to send reset link.";
        });
      }
    } catch (_) {
      setState(() {
        message = "Something went wrong.";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Forgot Password")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("Enter your email to receive a reset link."),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: isLoading ? null : sendResetRequest,
              child: isLoading
                  ? const CircularProgressIndicator()
                  : const Text("Send Reset Link"),
            ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(message, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
