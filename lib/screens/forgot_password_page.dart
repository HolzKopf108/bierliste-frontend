import 'package:flutter/material.dart';
import '../services/auth_api_service.dart';
import '../utils/navigation_helper.dart';

class ForgotPasswordPage extends StatefulWidget {
  final String email;

  const ForgotPasswordPage({super.key, required this.email});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  final _apiService = AuthApiService();

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.email;
  }

  void _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final error = await _apiService.resetPassword(
      email: _emailController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if(error == null) {
      safePushReplacementNamed(context, '/passwordVerify', arguments: _emailController.text.trim());
    }
    else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Login fehlgeschlagen'),
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
      appBar: AppBar(title: const Text('Passwort zurücksetzen')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Gib deine E-Mail-Adresse ein',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty || !value.contains('@')) {
                      return 'Bitte gültige E-Mail eingeben';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _submitEmail,
                        child: const Text('Bestätigen'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
