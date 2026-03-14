class AuthTokenResponse {
  final String accessToken;
  final String refreshToken;
  final String userEmail;

  const AuthTokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.userEmail,
  });

  factory AuthTokenResponse.fromJson(Map<String, dynamic> json) {
    final accessToken = (json['accessToken'] ?? '').toString().trim();
    final refreshToken = (json['refreshToken'] ?? '').toString().trim();
    final userEmail = (json['userEmail'] ?? '').toString().trim();

    if (accessToken.isEmpty || refreshToken.isEmpty || userEmail.isEmpty) {
      throw const FormatException('Ungültige Token-Response');
    }

    return AuthTokenResponse(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userEmail: userEmail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'userEmail': userEmail,
    };
  }
}
