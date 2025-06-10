import 'package:flutter/material.dart';
import '../models/counter.dart';
import '../services/api_service.dart';

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  final ApiService _apiService = ApiService();
  int _counter = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCounter();
  }

  Future<void> _loadCounter() async {
    final result = await _apiService.fetchCounter();
    if (result != null) {
      setState(() {
        _counter = result.count;
        _isLoading = false;
      });
    }
  }

  Future<void> _incrementCounter() async {
    setState(() => _counter++);
    final success = await _apiService.updateCounter(Counter(count: _counter));
    if (!success) debugPrint("Fehler beim Senden");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bier-Zähler'),
        leading: IconButton(
          icon: const Icon(Icons.group),
          onPressed: () {
            Navigator.pushNamed(context, '/groups');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _incrementCounter,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(40),
                  shape: const CircleBorder(),
                ),
                child: Text(
                  '$_counter',
                  style: const TextStyle(fontSize: 32),
                ),
              ),
      ),
    );
  }
}
