import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'FirebaseOptions have not been configured for web. '
        'Run flutterfire configure or provide web options manually.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'FirebaseOptions have not been configured for iOS. '
          'Run flutterfire configure to generate them.',
        );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        throw UnsupportedError(
          'FirebaseOptions have not been configured for desktop. '
          'Run flutterfire configure to generate them.',
        );
      default:
        throw UnsupportedError(
          'FirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDqDqXusVKeqEMGR857AzUt65kev7-Q3qo',
    appId: '1:445549586617:android:4120e91501a51b9c755368',
    messagingSenderId: '445549586617',
    projectId: 'qhomeapp',
    storageBucket: 'qhomeapp.firebasestorage.app',
  );
}


