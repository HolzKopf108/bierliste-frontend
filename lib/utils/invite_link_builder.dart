import 'package:bierliste/config/app_config.dart';

class InviteLinkBuilder {
  static Uri buildAppUri(String token) {
    return Uri(
      scheme: AppConfig.inviteScheme,
      host: AppConfig.inviteAppHost,
      queryParameters: {'token': token},
    );
  }

  static Uri buildShareUri(String token) {
    final baseUri = Uri.parse(AppConfig.publicBaseUrl);
    return baseUri.replace(
      pathSegments: [
        ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        'invites',
        token,
      ],
    );
  }

  static String buildAppLink(String token) => buildAppUri(token).toString();

  static String buildShareLink(String token) => buildShareUri(token).toString();
}
