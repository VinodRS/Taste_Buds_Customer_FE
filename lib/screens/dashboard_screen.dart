import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../services/location_service.dart';
import '../services/token_service.dart';
import 'offer_details_screen.dart';
import 'active_offers_screen.dart'; // <-- NEW

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  GoogleMapController? mapController;
  LatLng currentLocation = const LatLng(-33.8688, 151.2093); // fallback: Sydney
  Set<Circle> offerCircles = {};
  int activeOffers = 0;
  Map<String, dynamic>? bestOffer;
  int favouriteCount = 0;
  int pendingClaims = 0;
  List<dynamic> notifications = [];
  int notifCount = 0; // <-- NEW: total unread/active notifications to show
  bool isLoading = true;
  bool _isFetching = false; // avoid overlapping fetches

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fetchDashboardData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    mapController?.dispose();
    super.dispose();
  }

  // Refresh when app resumes (e.g., opened from a notification)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      fetchDashboardData();
    }
  }

  Future<void> fetchDashboardData() async {
    if (_isFetching) return; // debouncing
    _isFetching = true;

    setState(() => isLoading = true);

    final position = await getCurrentLocation();
    if (position == null) {
      debugPrint("❌ Could not get location, fallback to Sydney.");
      setState(() {
        isLoading = false;
        _isFetching = false;
      });
      return;
    }

    currentLocation = LatLng(position.latitude, position.longitude);

    final token = await getValidAccessToken();
    if (token == null) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
      setState(() => _isFetching = false);
      return;
    }

    final headers = {'Authorization': 'Bearer $token'};
    final lat = position.latitude;
    final lon = position.longitude;

    try {
      // Send location update
      await http.post(
        Uri.parse('http://192.168.86.37:8601/api/customer/location-update'),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'latitude': lat, 'longitude': lon}),
      );

      final offerRes = await http.get(
        Uri.parse(
            'http://192.168.86.37:8601/api/customer/nearby-offers?lat=$lat&lon=$lon'),
        headers: headers,
      );
      final favRes = await http.get(
        Uri.parse('http://192.168.86.37:8601/api/customer/favourites'),
        headers: headers,
      );
      final historyRes = await http.get(
        Uri.parse('http://192.168.86.37:8601/api/customer/history'),
        headers: headers,
      );
      final notifRes = await http.get(
        Uri.parse('http://192.168.86.37:8601/api/customer/notifications'),
        headers: headers,
      );

      if (offerRes.statusCode == 200) {
        final List<dynamic> offers = jsonDecode(offerRes.body);

        offers.sort((a, b) {
          final da = double.tryParse(a['discount'].toString()) ?? 0.0;
          final db = double.tryParse(b['discount'].toString()) ?? 0.0;
          return db.compareTo(da);
        });

        activeOffers = offers.length;
        bestOffer =
        offers.isNotEmpty ? (offers.first as Map<String, dynamic>) : null;

        offerCircles = offers.map<Circle?>((raw) {
          final offer = raw as Map<String, dynamic>;
          final rest = offer['restaurant'] as Map<String, dynamic>?;
          if (rest == null) return null;

          final latStr = rest['location_latitude']?.toString();
          final lonStr = rest['location_longitude']?.toString();
          final plat = double.tryParse(latStr ?? '');
          final plon = double.tryParse(lonStr ?? '');
          if (plat == null || plon == null) return null;

          return Circle(
            circleId: CircleId(offer['id'].toString()),
            center: LatLng(plat, plon),
            radius: 150,
            fillColor: Colors.blue.withOpacity(0.4),
            strokeColor: Colors.blueAccent.withOpacity(0.3),
            strokeWidth: 1,
          );
        }).whereType<Circle>().toSet();
      }

      if (favRes.statusCode == 200) {
        favouriteCount = (jsonDecode(favRes.body) as List).length;
      }

      if (historyRes.statusCode == 200) {
        final history = jsonDecode(historyRes.body) as List;
        pendingClaims =
            history.where((o) => o['status'] == 'claimed').length;
      }

      if (notifRes.statusCode == 200) {
        notifications = jsonDecode(notifRes.body) as List;

        // Compute "active/unread" notifications count locally.
        // (Matches backend active_notifications if you prefer to call /customer/dashboard)
        notifCount = notifications
            .where((n) => (n['opened'] == false) || (n['opened'] == 0))
            .length;
      }

      if (mapController != null) {
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(currentLocation, 14),
        );
      }
    } catch (e) {
      debugPrint('Error fetching dashboard data: $e');
    }

    if (!mounted) {
      _isFetching = false;
      return;
    }

    setState(() {
      isLoading = false;
      _isFetching = false;
    });
  }

  Future<void> _openOfferById(dynamic offerId) async {
    if (offerId == null) return;
    final token = await getValidAccessToken();
    if (token == null) return;

    try {
      await fetchDashboardData();

      if (bestOffer != null &&
          bestOffer!['id'].toString() == offerId.toString()) {
        await _claimAndNavigate(bestOffer!);
        return;
      }

      final pos = await getCurrentLocation();
      if (pos == null) return;

      final headers = {'Authorization': 'Bearer $token'};
      final res = await http.get(
        Uri.parse(
            'http://192.168.86.37:8601/api/customer/nearby-offers?lat=${pos.latitude}&lon=${pos.longitude}'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final offers = (jsonDecode(res.body) as List)
            .cast<Map<String, dynamic>>();
        final match = offers.firstWhere(
              (o) => o['id'].toString() == offerId.toString(),
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          await _claimAndNavigate(match);
        }
      }
    } catch (e) {
      debugPrint('Open offer by id error: $e');
    }
  }

  Future<void> _claimAndNavigate(Map<String, dynamic> offer) async {
    final token = await getValidAccessToken();
    if (token == null) return;

    final response = await http.post(
      Uri.parse('http://192.168.86.37:8601/api/customer/accept-offer'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'offer_id': offer['id']}),
    );

    if (response.statusCode == 201) {
      final claimed = jsonDecode(response.body);
      offer['qr_image'] = claimed['qr_url'];

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OfferDetailsScreen(offer: offer)),
      );

      if (mounted) fetchDashboardData();
    } else {
      debugPrint("❌ Offer claim failed: ${response.body}");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to claim offer")),
      );
    }
  }

  String _discountLabel(Map<String, dynamic> offer) {
    final discount = offer['discount'];
    final type = offer['type']; // "percentage" | "dollar"
    if (type == 'percentage') return "Discount: ${discount.toString()}%";
    if (type == 'dollar') return "Discount: \$${discount.toString()}";
    return "Discount: ${discount.toString()}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer Dashboard"),
        actions: [
          // Optional: simple badge in the AppBar
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  const Icon(Icons.notifications),
                  const SizedBox(width: 4),
                  Text('$notifCount'),
                ],
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchDashboardData),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Map
          Expanded(
            flex: 2,
            child: GoogleMap(
              onMapCreated: (controller) {
                mapController = controller;
                mapController!.animateCamera(
                  CameraUpdate.newLatLngZoom(currentLocation, 14),
                );
              },
              initialCameraPosition: CameraPosition(
                target: currentLocation,
                zoom: 14,
              ),
              circles: offerCircles,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          ),

          // Info + lists
          Expanded(
            child: RefreshIndicator(
              onRefresh: fetchDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row with "See all" button -> ActiveOffersScreen
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("🔥 Active Offers: $activeOffers",
                            style: const TextStyle(fontSize: 18)),
                        TextButton.icon(
                          icon: const Icon(Icons.list_alt),
                          label: const Text("See all"),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ActiveOffersScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Notifications count line
                    Text("🔔 Notifications: $notifCount",
                        style: const TextStyle(fontSize: 16)),

                    const SizedBox(height: 10),

                    if (bestOffer != null)
                      Card(
                        child: ListTile(
                          title: Text(bestOffer!['offer_name'] ?? 'Best Offer'),
                          subtitle: Text(_discountLabel(bestOffer!)),
                          trailing: const Icon(Icons.arrow_forward),
                          onTap: () => _claimAndNavigate(bestOffer!),
                        ),
                      ),

                    const SizedBox(height: 10),
                    Text("❤️ Favorite Restaurants: $favouriteCount",
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 10),
                    Text("🎟️ Pending Claims: $pendingClaims",
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 16),

                    const Text("🛎️ Notifications:",
                        style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 8),

                    ...notifications.map((n) {
                      final offerId = n['offer_id'] ??
                          ((n['offer'] is Map<String, dynamic>)
                              ? (n['offer'] as Map<String, dynamic>)['id']
                              : null);
                      final title = n['title'] ?? 'Offer';
                      final message =
                          n['message'] ?? 'New offer available nearby';
                      return Card(
                        child: ListTile(
                          title: Text(title),
                          subtitle: Text(message),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            if (offerId != null) {
                              await _openOfferById(offerId);
                            } else if (bestOffer != null) {
                              await _claimAndNavigate(bestOffer!);
                            }
                            if (mounted) fetchDashboardData();
                          },
                        ),
                      );
                    }),

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
