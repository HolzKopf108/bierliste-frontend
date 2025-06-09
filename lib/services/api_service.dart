import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/counter.dart';

class ApiService {
  Future<Counter?> fetchCounter() async {
    try {
      final response = await http.get(Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.counter}'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Counter.fromJson(data);
      }
    } catch (e) {
      debugPrint('Fehler beim Laden: $e');
    }
    return null;
  }

  Future<bool> updateCounter(Counter counter) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.counter}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(counter.toJson()),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Fehler beim Senden: $e');
      return false;
    }
  }
}
