import 'package:flutter/material.dart';
import 'package:bierliste/services/auth_api_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _passwordVisible = false;

  final _apiService = AuthApiService();

  void _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final error = await _apiService.loginUser(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      authProvider: authProvider,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pushReplacementNamed('/');
    } 
    else if (error.contains('Email nicht verifiziert')) {
      Navigator.of(context).pushReplacementNamed('/verify', arguments: _emailController.text.trim());
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

  void _navigateToRegister() {
    Navigator.of(context).pushNamed('/register');
  }

  void _loginGoogle() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'],
      );

      final googleUser = await googleSignIn.signIn();
      final googleAuth = await googleUser?.authentication;
      final idToken = googleAuth?.idToken;

      debugPrint('Google user: $googleUser');
      debugPrint('Google auth: $googleAuth');
      debugPrint('ID Token: $idToken');

      if (idToken == null) {
        _showError('Google Login fehlgeschlagen');
        return;
      }

      if (!mounted) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final error = await _apiService.loginGoogle(idToken, authProvider);

      if (!mounted) return;

      if (error == null) {
        Navigator.of(context).pushReplacementNamed('/');
      } else {
        _showError(error);
      }
    } catch (e) {
      _showError('Google Login nicht möglich: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  //void _loginApple() { }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fehler'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          )
        ],
      ),
    );
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
                    'Bierliste Login',
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
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/forgotPassword', arguments: _emailController.text.trim());
                    },
                    child: const Text('Passwort vergessen?'),
                  ),
                  const SizedBox(height: 16),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                            child: const Text('Anmelden'),
                          ),
                        ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _navigateToRegister,
                    child: const Text("Noch kein Konto? Jetzt registrieren"),
                  ),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _loginGoogle();
                      },
                      icon: const Icon(Icons.login),
                      label: const Text('Mit Google anmelden'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: null, // () {
                        /// _loginApple();
                      //  },
                      icon: const Icon(Icons.apple),
                      label: const Text('Mit Apple anmelden'),
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
