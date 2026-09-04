class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.distanceLabel,
    this.isRecent = false,
  });

  final String title;
  final String subtitle;
  final String address;
  final double latitude;
  final double longitude;
  final String? distanceLabel;
  final bool isRecent;
}

class PlaceSuggestionService {
  const PlaceSuggestionService._();

  static String primaryPlaceName(String address) {
    final parts = address.split(',');
    return parts.first.trim().isEmpty ? address : parts.first.trim();
  }

  static List<PlaceSuggestion> suggestionsFor(
    String query, {
    List<PlaceSuggestion> recent = const [],
    int limit = 8,
  }) {
    final cleaned = query.trim().toLowerCase();
    final source = [
      ...recent,
      ...nigeriaPlaceCatalog.where((place) {
        return !recent.any(
          (recentPlace) =>
              recentPlace.address.toLowerCase() == place.address.toLowerCase(),
        );
      }),
    ];

    if (cleaned.isEmpty) return source.take(limit).toList();

    final startsWith = source
        .where((place) => place.title.toLowerCase().startsWith(cleaned))
        .toList();
    final contains = source
        .where(
          (place) =>
              !startsWith.contains(place) &&
              place.address.toLowerCase().contains(cleaned),
        )
        .toList();

    return [...startsWith, ...contains].take(limit).toList();
  }
}

const nigeriaPlaceCatalog = [
  PlaceSuggestion(
    title: 'Lagos Island',
    subtitle: 'Lagos, Nigeria',
    address: 'Lagos Island, Lagos, Nigeria',
    latitude: 6.4541,
    longitude: 3.3947,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Ikeja',
    subtitle: 'Lagos, Nigeria',
    address: 'Ikeja, Lagos, Nigeria',
    latitude: 6.6018,
    longitude: 3.3515,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Lekki Phase 1',
    subtitle: 'Lagos, Nigeria',
    address: 'Lekki Phase 1, Lagos, Nigeria',
    latitude: 6.4474,
    longitude: 3.4723,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Victoria Island',
    subtitle: 'Lagos, Nigeria',
    address: 'Victoria Island, Lagos, Nigeria',
    latitude: 6.4281,
    longitude: 3.4219,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Ajah',
    subtitle: 'Lagos, Nigeria',
    address: 'Ajah, Lagos, Nigeria',
    latitude: 6.4698,
    longitude: 3.5852,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Lugbe',
    subtitle: 'Abuja, Nigeria',
    address: 'Lugbe, Abuja, Nigeria',
    latitude: 9.0068,
    longitude: 7.3572,
    distanceLabel: '92 mi',
  ),
  PlaceSuggestion(
    title: 'Lugbe Plaza Abuja',
    subtitle: 'Abuja, Nigeria',
    address: 'Lugbe Plaza, Abuja, Nigeria',
    latitude: 9.0083,
    longitude: 7.3589,
    distanceLabel: '93 mi',
  ),
  PlaceSuggestion(
    title: 'CBN Quarters Lugbe',
    subtitle: 'Abuja, Nigeria',
    address: 'CBN Quarters Lugbe, Abuja, Nigeria',
    latitude: 9.0112,
    longitude: 7.3707,
    distanceLabel: '93 mi',
  ),
  PlaceSuggestion(
    title: 'Abuja',
    subtitle: 'Federal Capital Territory, Nigeria',
    address: 'Abuja, Federal Capital Territory, Nigeria',
    latitude: 9.0765,
    longitude: 7.3986,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Wuse',
    subtitle: 'Abuja, Nigeria',
    address: 'Wuse, Abuja, Federal Capital Territory, Nigeria',
    latitude: 9.0767,
    longitude: 7.4703,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Garki',
    subtitle: 'Abuja, Nigeria',
    address: 'Garki, Abuja, Federal Capital Territory, Nigeria',
    latitude: 9.0362,
    longitude: 7.4913,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Maitama',
    subtitle: 'Abuja, Nigeria',
    address: 'Maitama, Abuja, Federal Capital Territory, Nigeria',
    latitude: 9.0969,
    longitude: 7.4951,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Gwarinpa',
    subtitle: 'Abuja, Nigeria',
    address: 'Gwarinpa, Abuja, Federal Capital Territory, Nigeria',
    latitude: 9.1099,
    longitude: 7.4042,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Kubwa',
    subtitle: 'Abuja, Nigeria',
    address: 'Kubwa, Abuja, Federal Capital Territory, Nigeria',
    latitude: 9.1538,
    longitude: 7.322,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Nyanya',
    subtitle: 'Abuja, Nigeria',
    address: 'Nyanya, Abuja, Federal Capital Territory, Nigeria',
    latitude: 9.0271,
    longitude: 7.5747,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Jabi',
    subtitle: 'Abuja, Nigeria',
    address: 'Jabi, Abuja, Federal Capital Territory, Nigeria',
    latitude: 9.0643,
    longitude: 7.4217,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Kaduna',
    subtitle: 'Nigeria',
    address: 'Kaduna, Nigeria',
    latitude: 10.5105,
    longitude: 7.4165,
    distanceLabel: '192 mi',
  ),
  PlaceSuggestion(
    title: 'Kaduna South',
    subtitle: 'Kaduna, Nigeria',
    address: 'Kaduna South, Kaduna, Nigeria',
    latitude: 10.4697,
    longitude: 7.4411,
    distanceLabel: '188 mi',
  ),
  PlaceSuggestion(
    title: 'Kaduna International Airport',
    subtitle: 'Kaduna, Nigeria',
    address: 'Kaduna International Airport, Kaduna, Nigeria',
    latitude: 10.696,
    longitude: 7.3201,
    distanceLabel: '203 mi',
  ),
  PlaceSuggestion(
    title: 'Lokoja International Stadium',
    subtitle: 'Lokoja, Kogi, Nigeria',
    address: 'Lokoja International Stadium, Lokoja, Kogi, Nigeria',
    latitude: 7.8093,
    longitude: 6.7388,
    distanceLabel: '154 mi',
  ),
  PlaceSuggestion(
    title: 'Federal University Lokoja',
    subtitle: 'Felele Campus, Lokoja, Nigeria',
    address: 'Federal University Lokoja, Felele Campus, Lokoja, Nigeria',
    latitude: 7.7542,
    longitude: 6.7551,
    distanceLabel: '151 mi',
  ),
  PlaceSuggestion(
    title: 'Port Harcourt',
    subtitle: 'Rivers, Nigeria',
    address: 'Port Harcourt, Rivers, Nigeria',
    latitude: 4.8156,
    longitude: 7.0498,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Ibadan',
    subtitle: 'Oyo, Nigeria',
    address: 'Ibadan, Oyo, Nigeria',
    latitude: 7.3775,
    longitude: 3.947,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Kano',
    subtitle: 'Kano, Nigeria',
    address: 'Kano, Kano, Nigeria',
    latitude: 12.0022,
    longitude: 8.592,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Enugu',
    subtitle: 'Enugu, Nigeria',
    address: 'Enugu, Enugu, Nigeria',
    latitude: 6.5244,
    longitude: 7.5086,
    distanceLabel: 'near',
  ),
  PlaceSuggestion(
    title: 'Benin City',
    subtitle: 'Edo, Nigeria',
    address: 'Benin City, Edo, Nigeria',
    latitude: 6.335,
    longitude: 5.6037,
    distanceLabel: 'near',
  ),
];
