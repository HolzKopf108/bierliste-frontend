import 'package:bierliste/utils/navigation_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bierliste/services/auth_api_service.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class VerifyPage extends StatefulWidget {
  final String email;

  const VerifyPage({super.key, required this.email});

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _apiService = AuthApiService();
  bool _isLoading = false;

  Future<void> _submitCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final error = await _apiService.verifyEmail(
      email: widget.email,
      code: _codeController.text.trim(),
      authProvider: authProvider,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (error == null) {
      safePushReplacementNamed(context, '/');
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Fehler'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            )
          ],
        ),
      );
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);

    final error = await _apiService.resendVerificationCode(email: widget.email);

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Neuer Code gesendet.')),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Fehler'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            )
          ],
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Text(
                    'E-Mail bestätigen',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Ein 6-stelliger Bestätigungscode wurde an\n${widget.email}\n gesendet.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Schau auch im Spam-Ordner nach!',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Bestätigungscode',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    validator: (value) {
                      if (value == null || value.length != 6) {
                        return 'Code muss 6-stellig sein';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submitCode,
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                            child: const Text('Verifizieren'),
                          ),
                        ),
                  const SizedBox(height: 24),
                  _isLoading
                    ? const SizedBox(height: 48)
                    : TextButton(
                        onPressed: _resendCode,
                        child: const Text('Code erneut senden'),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
