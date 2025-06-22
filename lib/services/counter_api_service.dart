import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../models/counter.dart';
import 'http_service.dart';
import 'offline_strich_service.dart';

class CounterApiService {
  Future<Counter?> fetchCounter() async {
    try {
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.counter}',
        'GET',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Counter.fromJson(data);
      } else {
        debugPrint('Unerwarteter Statuscode beim fetch: ${response.statusCode}');
      }
    } on UnauthorizedException {
      debugPrint('Nicht autorisiert - fetchCounter');
      rethrow;
    } catch (e) {
      debugPrint('Fehler beim Laden des Counters: $e');
    }

    return null;
  }

  Future<bool> updateCounter(int count) async {
    try {
      final response = await HttpService.authorizedRequest(
        '${AppConfig.apiBaseUrl}${AppConfig.apiVersion}${AppConfig.counter}',
        'POST',
        body: {'count': count},
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        debugPrint('Update fehlgeschlagen mit Code: ${response.statusCode}');
      }
    } on UnauthorizedException {
      debugPrint('Nicht autorisiert beim Update');
      rethrow;
    } catch (e) {
      debugPrint('Fehler beim Aktualisieren des Counters: $e');
    }

    return false;
  }

  Future<bool> syncPendingStriche(String userEmail) async {
    final total = await OfflineStrichService.getPendingSum(userEmail);
    if (total == 0) return true;

    final success = await updateCounter(total);
    if (success) {
      await OfflineStrichService.clearPendingStriche(userEmail);
    }
    return success;
  }
}
