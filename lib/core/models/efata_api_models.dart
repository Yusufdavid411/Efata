double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _dateValue(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

class EfataAccount {
  const EfataAccount({
    required this.uid,
    required this.email,
    required this.role,
    required this.displayName,
    required this.accountStatus,
    required this.emailVerified,
    required this.profileCompleted,
    this.phone,
    this.photoUrl,
    this.customerProfile,
    this.driverProfile,
  });

  final String uid;
  final String email;
  final String role;
  final String displayName;
  final String accountStatus;
  final bool emailVerified;
  final bool profileCompleted;
  final String? phone;
  final String? photoUrl;
  final Map<String, dynamic>? customerProfile;
  final Map<String, dynamic>? driverProfile;

  factory EfataAccount.fromJson(Map<String, dynamic> json) => EfataAccount(
    uid: json['uid']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    displayName: json['displayName']?.toString() ?? '',
    accountStatus: json['accountStatus']?.toString() ?? '',
    emailVerified: json['emailVerified'] == true,
    profileCompleted: json['profileCompleted'] == true,
    phone: json['phone']?.toString(),
    photoUrl: json['photoUrl']?.toString(),
    customerProfile: (json['customerProfile'] as Map?)?.cast<String, dynamic>(),
    driverProfile: (json['driverProfile'] as Map?)?.cast<String, dynamic>(),
  );
}

class EfataOrder {
  const EfataOrder({
    required this.id,
    required this.status,
    required this.pickup,
    required this.dropoff,
    required this.item,
    required this.vehicleType,
    required this.paymentMethod,
    required this.amount,
    required this.unreadForCustomer,
    required this.unreadForDriver,
    this.legacyId,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.paymentStatus,
    this.scheduledFor,
    this.distanceMeters,
    this.durationSeconds,
    this.lastMessage,
    this.lastMessageAt,
    this.createdAt,
    this.updatedAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String? legacyId;
  final String status;
  final String pickup;
  final double? pickupLat;
  final double? pickupLng;
  final String dropoff;
  final double? dropoffLat;
  final double? dropoffLng;
  final String item;
  final String vehicleType;
  final String paymentMethod;
  final String? paymentStatus;
  final double amount;
  final DateTime? scheduledFor;
  final int? distanceMeters;
  final int? durationSeconds;
  final int unreadForCustomer;
  final int unreadForDriver;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  factory EfataOrder.fromJson(Map<String, dynamic> json) => EfataOrder(
    id: json['id']?.toString() ?? '',
    legacyId: json['legacyId']?.toString(),
    status: json['status']?.toString() ?? '',
    pickup: json['pickup']?.toString() ?? '',
    pickupLat: _doubleValue(json['pickupLat']),
    pickupLng: _doubleValue(json['pickupLng']),
    dropoff: json['dropoff']?.toString() ?? '',
    dropoffLat: _doubleValue(json['dropoffLat']),
    dropoffLng: _doubleValue(json['dropoffLng']),
    item: json['item']?.toString() ?? '',
    vehicleType: json['vehicleType']?.toString() ?? '',
    paymentMethod: json['paymentMethod']?.toString() ?? '',
    paymentStatus: json['paymentStatus']?.toString(),
    amount: _doubleValue(json['amount']) ?? 0,
    scheduledFor: _dateValue(json['scheduledFor']),
    distanceMeters: _intValue(json['distanceMeters']),
    durationSeconds: _intValue(json['durationSeconds']),
    unreadForCustomer: _intValue(json['unreadForCustomer']) ?? 0,
    unreadForDriver: _intValue(json['unreadForDriver']) ?? 0,
    lastMessage: json['lastMessage']?.toString(),
    lastMessageAt: _dateValue(json['lastMessageAt']),
    createdAt: _dateValue(json['createdAt']),
    updatedAt: _dateValue(json['updatedAt']),
    acceptedAt: _dateValue(json['acceptedAt']),
    startedAt: _dateValue(json['startedAt']),
    completedAt: _dateValue(json['completedAt']),
  );
}

class EfataOrderPage {
  const EfataOrderPage({required this.orders, this.nextPage});

  final List<EfataOrder> orders;
  final int? nextPage;

  factory EfataOrderPage.fromJson(Map<String, dynamic> json) => EfataOrderPage(
    orders: (json['orders'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => EfataOrder.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false),
    nextPage: _intValue(json['nextPage']),
  );
}

class EfataMessage {
  const EfataMessage({
    required this.id,
    required this.senderRole,
    required this.body,
    this.senderName,
    this.createdAt,
  });

  final String id;
  final String senderRole;
  final String body;
  final String? senderName;
  final DateTime? createdAt;

  factory EfataMessage.fromJson(Map<String, dynamic> json) => EfataMessage(
    id: json['id']?.toString() ?? '',
    senderRole: json['senderRole']?.toString() ?? '',
    body: json['body']?.toString() ?? '',
    senderName: json['senderName']?.toString(),
    createdAt: _dateValue(json['createdAt']),
  );
}

class EfataMessagePage {
  const EfataMessagePage({required this.messages, this.nextPage});

  final List<EfataMessage> messages;
  final int? nextPage;

  factory EfataMessagePage.fromJson(Map<String, dynamic> json) =>
      EfataMessagePage(
        messages: (json['messages'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => EfataMessage.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false),
        nextPage: _intValue(json['nextPage']),
      );
}

class EfataDriverTracking {
  const EfataDriverTracking({
    required this.lat,
    required this.lng,
    this.heading,
    this.updatedAt,
    this.isOnline,
  });

  final double lat;
  final double lng;
  final double? heading;
  final DateTime? updatedAt;
  final bool? isOnline;

  factory EfataDriverTracking.fromJson(Map<String, dynamic> json) =>
      EfataDriverTracking(
        lat: _doubleValue(json['lat']) ?? 0,
        lng: _doubleValue(json['lng']) ?? 0,
        heading: _doubleValue(json['heading']),
        updatedAt: _dateValue(json['updatedAt']),
        isOnline: json['isOnline'] as bool?,
      );
}
