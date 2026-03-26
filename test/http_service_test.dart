import 'dart:convert';
import 'dart:io';

import 'package:bierliste/services/http_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HttpServer? server;
  Uri? serverUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverUri = Uri.parse('http://${server!.address.address}:${server!.port}');
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    serverUri = null;
  });

  test('POST without body does not send a JSON content type header', () async {
    final requestFuture = server!.first;
    final responseFuture = HttpService.unauthorizedRequest(
      serverUri!.toString(),
      'POST',
    );

    final request = await requestFuture;
    final body = await utf8.decoder.bind(request).join();
    expect(request.headers.contentType, isNull);
    expect(body, isEmpty);

    request.response
      ..statusCode = 200
      ..write('{}');
    await request.response.close();

    final response = await responseFuture;
    expect(response.statusCode, 200);
  });

  test(
    'POST with body sends JSON content type and encoded JSON body',
    () async {
      final requestFuture = server!.first;
      final responseFuture = HttpService.unauthorizedRequest(
        serverUri!.toString(),
        'POST',
        body: const {'amount': 1},
      );

      final request = await requestFuture;
      final body = await utf8.decoder.bind(request).join();
      expect(request.headers.contentType?.mimeType, 'application/json');
      expect(jsonDecode(body), {'amount': 1});

      request.response
        ..statusCode = 200
        ..write('{}');
      await request.response.close();

      final response = await responseFuture;
      expect(response.statusCode, 200);
    },
  );
}
