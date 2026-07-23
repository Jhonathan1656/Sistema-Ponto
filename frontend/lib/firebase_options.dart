import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDtE1kvZ2tnXJxMFT6gugigjkn-GrKS15o',
    authDomain: 'ponto-vmac.firebaseapp.com',
    projectId: 'ponto-vmac',
    storageBucket: 'ponto-vmac.firebasestorage.app',
    messagingSenderId: '702496632234',
    appId: '1:702496632234:web:62af882302344f38734fd3',
    measurementId: 'G-QND51815P3',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDtE1kvZ2tnXJxMFT6gugigjkn-GrKS15o',
    appId: '1:702496632234:android:ponto.vmac.app', // ID genérico, ajuste se necessário
    messagingSenderId: '702496632234',
    projectId: 'ponto-vmac',
    storageBucket: 'ponto-vmac.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDtE1kvZ2tnXJxMFT6gugigjkn-GrKS15o',
    appId: '1:702496632234:ios:62af882302344f38734fd3',
    messagingSenderId: '702496632234',
    projectId: 'ponto-vmac',
    storageBucket: 'ponto-vmac.firebasestorage.app',
    iosBundleId: 'com.example.pontoApp',
  );
}
