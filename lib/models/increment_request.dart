class IncrementRequest {
  final int amount;

  const IncrementRequest({required this.amount});

  Map<String, dynamic> toJson() {
    return {'amount': amount};
  }
}
