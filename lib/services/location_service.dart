import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  static Future<void> requestAndSaveLiveLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("NOT_LOGGED_IN");

    // 1) Location services açık mı?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception("LOCATION_SERVICE_DISABLED");

    // 2) Permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception("LOCATION_DENIED");
      }
    }

    if (permission == LocationPermission.denied) throw Exception("LOCATION_DENIED");
    if (permission == LocationPermission.deniedForever) throw Exception("LOCATION_DENIED_FOREVER");

    // 3) Position
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );

    // 4) City (reverse geocode) - başarısız olabilir, sıkıntı değil
    String? city;
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        city = placemarks.first.administrativeArea; // TR’de genelde şehir
        city = city?.trim();
        if (city != null && city.isEmpty) city = null;
      }
    } catch (_) {}

    // 5) Firestore write
    await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
      "geo": GeoPoint(pos.latitude, pos.longitude),
      if (city != null) "location": city,
      "locationSource": "gps",
      "locationUpdatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> saveManualCity(String city) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("NOT_LOGGED_IN");

    final cleaned = city.trim();
    if (cleaned.isEmpty) throw Exception("CITY_EMPTY");

    await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
      "location": cleaned,
      "locationSource": "manual",
      "locationUpdatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
