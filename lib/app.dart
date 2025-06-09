import 'package:flutter/material.dart';
// oder später group_page.dart
import 'screens/loading_page.dart';

class BierlisteApp extends StatelessWidget {
  const BierlisteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bierliste',
      theme: ThemeData(primarySwatch: Colors.brown),
      home: const LoadingPage(), // Entscheidet später dynamisch
    );
  }
}
