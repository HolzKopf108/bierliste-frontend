import 'package:bierliste/services/api_service.dart';
import 'package:flutter/material.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _apiService = ApiService(); 

  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _passwordVisible2 = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final error = await _apiService.registerUser(
      email: _emailController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pushReplacementNamed('/verify', arguments: _emailController.text.trim());
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
            ),
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
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Registrieren',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty || !value.contains('@')) {
                        return 'Bitte gültige Email eingeben';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Benutzername',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 3) {
                        return 'Benutzername zu kurz';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_passwordVisible,
                    decoration: InputDecoration(
                      labelText: 'Passwort',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _passwordVisible ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => _passwordVisible = !_passwordVisible);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 8) {
                        return 'Passwort muss mindestens 8 Zeichen lang sein';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: !_passwordVisible2,
                    decoration: InputDecoration(
                      labelText: 'Passwort bestätigen',
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _passwordVisible2 ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() => _passwordVisible2 = !_passwordVisible2);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Passwörter stimmen nicht überein';
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
                            onPressed: _register,
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                            child: const Text('Registrieren'),
                          ),
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
