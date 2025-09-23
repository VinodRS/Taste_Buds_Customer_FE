// screens/offer_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/token_service.dart';

class OfferDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> offer;
  const OfferDetailsScreen({super.key, required this.offer});

  String _discountLabel(Map<String, dynamic> offer) {
    final discount = offer['discount'];
    final type = offer['type']; // "percentage" | "dollar"
    if (type == 'percentage') return "Discount: ${discount.toString()}%";
    if (type == 'dollar') return "Discount: \$${discount.toString()}";
    return "Discount: ${discount.toString()}";
  }

  Future<void> _claimIfNeeded(BuildContext context) async {
    // If QR already present, nothing to do
    if (offer['qr_image'] != null) return;

    final token = await getValidAccessToken();
    if (token == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please login again.')),
        );
      }
      return;
    }

    final res = await http.post(
      Uri.parse('http://192.168.86.37:8601/api/customer/accept-offer'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'offer_id': offer['id']}),
    );

    if (res.statusCode == 201) {
      final claimed = jsonDecode(res.body);
      offer['qr_image'] = claimed['qr_url'];
      if (context.mounted) {
        // Force rebuild to show QR
        (context as Element).markNeedsBuild();
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to claim offer')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = offer['offer_name'] ?? offer['title'] ?? 'Offer Details';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Description: ${offer['description'] ?? 'N/A'}",
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text(_discountLabel(offer), style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),

            if (offer['qr_image'] != null)
              Center(
                child: Image.network(
                  offer['qr_image'],
                  height: 200,
                  width: 200,
                ),
              )
            else
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.confirmation_num),
                  label: const Text('Claim to show QR'),
                  onPressed: () => _claimIfNeeded(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
