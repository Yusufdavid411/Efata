import 'package:geolocator/geolocator.dart';

enum LocationAccessStatus {
  granted,
  serviceDisabled,
  denied,
  deniedForever,
  unavailable,
}

class LocationService {
  static Future<LocationAccessStatus> requestLocationAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return LocationAccessStatus.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return LocationAccessStatus.denied;
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationAccessStatus.deniedForever;
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return LocationAccessStatus.granted;
    }

    return LocationAccessStatus.unavailable;
  }

  static Future<bool> requestLocationPermission() async {
    return await requestLocationAccess() == LocationAccessStatus.granted;
  }

  static Future<Position?> getCurrentPosition() async {
    final access = await requestLocationAccess();
    if (access != LocationAccessStatus.granted) return null;

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }

  static Stream<Position> getLiveLocationStream() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
