import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const currentPlatform = FirebaseOptions(
    apiKey: 'test-api-key',
    appId: 'test-app-id',
    messagingSenderId: 'test-sender',
    projectId: 'test-project',
  );
}
