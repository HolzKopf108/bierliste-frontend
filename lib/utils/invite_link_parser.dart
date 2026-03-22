class InviteLinkParser {
  static const _queryParameterKeys = ['token', 'inviteToken', 'invite'];
  static const _pathMarkers = ['invite', 'invites', 'join'];

  static String? parseToken(Uri? uri) {
    if (uri == null) {
      return null;
    }

    final directToken = _parseTokenFromUri(uri);
    if (directToken != null) {
      return directToken;
    }

    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) {
      return null;
    }

    final fragmentUri = _parseFragment(fragment);
    if (fragmentUri == null) {
      return null;
    }

    return _parseTokenFromUri(fragmentUri);
  }

  static Uri? _parseFragment(String fragment) {
    if (fragment.contains('://')) {
      return Uri.tryParse(fragment);
    }

    if (fragment.startsWith('/')) {
      return Uri.tryParse('https://invite.invalid$fragment');
    }

    if (fragment.contains('=')) {
      return Uri.tryParse('https://invite.invalid/?$fragment');
    }

    return Uri.tryParse('https://invite.invalid/$fragment');
  }

  static String? _parseTokenFromUri(Uri uri) {
    for (final key in _queryParameterKeys) {
      final value = _sanitizeToken(uri.queryParameters[key]);
      if (value != null) {
        return value;
      }
    }

    final normalizedHost = uri.host.trim().toLowerCase();
    if (_pathMarkers.contains(normalizedHost)) {
      final hostPathToken = uri.pathSegments.isNotEmpty
          ? _sanitizeToken(uri.pathSegments.first)
          : null;
      if (hostPathToken != null) {
        return hostPathToken;
      }
    }

    final segments = uri.pathSegments
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    if (segments.isEmpty) {
      return null;
    }

    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index].toLowerCase();
      if (_pathMarkers.contains(segment) && index + 1 < segments.length) {
        return _sanitizeToken(segments[index + 1]);
      }
    }

    final lastSegment = _sanitizeToken(segments.last);
    if (lastSegment == null || segments.length < 2) {
      return null;
    }

    final previousSegment = segments[segments.length - 2].toLowerCase();
    if (_pathMarkers.any(previousSegment.contains)) {
      return lastSegment;
    }

    return null;
  }

  static String? _sanitizeToken(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return Uri.decodeComponent(trimmed);
  }
}
