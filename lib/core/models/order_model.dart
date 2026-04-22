enum OrderStatus {
  pending,
  accepted,
  inTransit,
  completed,
}

class Order {
  final String id;
  final String pickup;
  final String dropoff;
  final String item;
  OrderStatus status;

  Order({
    required this.id,
    required this.pickup,
    required this.dropoff,
    required this.item,
    this.status = OrderStatus.pending,
  });
}
