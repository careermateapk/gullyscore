// Google sign-in for players. Only asks Google "who is this?" (name and
// email); nothing is posted and no other Google data is read.
import 'package:google_sign_in/google_sign_in.dart';

import 'cloud.dart';

class GoogleLoginError implements Exception {
  GoogleLoginError(this.cancelled, this.message);
  final bool cancelled;
  final String message;

  @override
  String toString() => 'GoogleLoginError($message)';
}

abstract class GoogleAuth {
  bool get available;

  /// Opens Google's account picker. Returns a sign-in token for our server.
  Future<String> idToken();
  Future<void> signOut();
}

class PluginGoogleAuth implements GoogleAuth {
  PluginGoogleAuth([this.clientId = googleClientId]);
  final String clientId;
  bool _ready = false;

  @override
  bool get available => clientId.trim().isNotEmpty;

  Future<void> _init() async {
    if (_ready) return;
    await GoogleSignIn.instance.initialize(serverClientId: clientId.trim());
    _ready = true;
  }

  @override
  Future<String> idToken() async {
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate();
      final t = account.authentication.idToken;
      if (t == null || t.isEmpty) throw GoogleLoginError(false, 'no token');
      return t;
    } on GoogleSignInException catch (e) {
      throw GoogleLoginError(e.code == GoogleSignInExceptionCode.canceled, '${e.code}: ${e.description}');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _init();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
