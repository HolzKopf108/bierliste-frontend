import 'package:bierliste/utils/invite_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses token from invite path', () {
    final token = InviteLinkParser.parseToken(
      Uri.parse('bierliste://invite/token-123'),
    );

    expect(token, 'token-123');
  });

  test('parses token from query parameter', () {
    final token = InviteLinkParser.parseToken(
      Uri.parse('bierliste://join?token=query-token'),
    );

    expect(token, 'query-token');
  });

  test('parses token from fragment path', () {
    final token = InviteLinkParser.parseToken(
      Uri.parse('https://bierliste.koelker-recke.de/#/invite/fragment-token'),
    );

    expect(token, 'fragment-token');
  });

  test('parses token from custom scheme host and path', () {
    final token = InviteLinkParser.parseToken(
      Uri.parse('bierliste://invites/custom-path-token'),
    );

    expect(token, 'custom-path-token');
  });
}
