import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/location_service.dart';
import '../services/token_service.dart';
import 'offer_details_screen.dart';

class ActiveOffersScreen extends StatefulWidget {
  const ActiveOffersScreen({super.key});

  @override
  State<ActiveOffersScreen> createState() => _ActiveOffersScreenState();
}

class _ActiveOffersScreenState extends State<ActiveOffersScreen> {
  bool loading = true;
  List<Map<String, dynamic>> offers = [];
  String? error;

  @override
  void initState() {
    super.initState();
    _loadOffers();
  }

  Future<void> _loadOffers() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final pos = await getCurrentLocation();
      if (pos == null) {
        setState(() {
          error = "Couldn't get location.";
          loading = false;
        });
        return;
      }

      final token = await getValidAccessToken();
      if (token == null) {
        setState(() {
          error = "Unauthorized. Please login again.";
          loading = false;
        });
        return;
      }

      final res = await http.get(
        Uri.parse(
          'http://192.168.86.37:8601/api/customer/active-offers?lat=${pos.latitude}&lon=${pos.longitude}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List)
            .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
            .toList();

        setState(() {
          offers = list;
          loading = false;
        });
      } else {
        setState(() {
          error = 'Failed to load offers (${res.statusCode})';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
        loading = false;
      });
    }
  }

  String _discountLabel(Map<String, dynamic> offer) {
    final discount = offer['discount'];
    final type = offer['type'];
    if (type == 'percentage') return "${discount.toString()}% off";
    if (type == 'dollar') return "\$${discount.toString()} off";
    return discount?.toString() ?? '';
  }

  Future<void> _claimAndOpen(Map<String, dynamic> offer) async {
    try {
      final token = await getValidAccessToken();
      if (token == null) return;

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
        // Provide QR for details screen
        offer['qr_image'] = claimed['qr_url'];
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OfferDetailsScreen(offer: offer)),
        );
        if (mounted) _loadOffers();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to claim: ${res.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : ListView.separated(
      itemCount: offers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final o = offers[i];
        final restaurant = (o['restaurant'] ?? {}) as Map<String, dynamic>;
        final rName = (restaurant['name'] ?? '').toString();

        return ListTile(
          title: Text(o['offer_name'] ?? o['title'] ?? 'Offer'),
          subtitle: Text([
            if (rName.isNotEmpty) rName,
            _discountLabel(o),
          ].where((x) => x.isNotEmpty).join(' • ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _claimAndOpen(o),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Active Offers Nearby')),
      body: RefreshIndicator(onRefresh: _loadOffers, child: body),
    );
  }
}
