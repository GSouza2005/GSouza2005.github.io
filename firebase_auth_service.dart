import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

class FirebaseAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Login com email e senha
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print('Erro no login: $e');
      rethrow; // Repassa o erro para ser tratado onde a função for chamada
    }
  }

  // Cadastro com email e senha
  Future<User?> signUpWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print('Erro no cadastro: $e');
      rethrow; // Repassa o erro para ser tratado onde a função for chamada
    }
  }

  // Login com Google
  Future<User?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        return null; // Usuário cancelou o login
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Once signed in, return the UserCredential
      final UserCredential userCredential = 
          await _auth.signInWithCredential(credential);
      
      return userCredential.user;
    } catch (e) {
      print('Erro no login com Google: $e');
      rethrow;
    }
  }

  // Login com Apple
  Future<User?> signInWithApple() async {
    try {
      // Para gerar nonce seguro
      String generateNonce([int length = 32]) {
        const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
        final random = Random.secure();
        return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
      }

      // Para criar um SHA256 hash do nonce
      String sha256ofString(String input) {
        final bytes = utf8.encode(input);
        final digest = sha256.convert(bytes);
        return digest.toString();
      }

      // Gerar nonce seguro para prevenção de ataques de repetição
      final rawNonce = generateNonce();
      final nonce = sha256ofString(rawNonce);

      // Solicitar credenciais da Apple
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // Criar credencial do Firebase Auth com o token da Apple
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      // Autenticar no Firebase
      final UserCredential userCredential = 
          await _auth.signInWithCredential(oauthCredential);
      
      // Se é a primeira vez que o usuário faz login, talvez precise armazenar o nome
      // pois a Apple só envia o nome na primeira vez
      if (appleCredential.givenName != null && 
          appleCredential.familyName != null) {
        await userCredential.user?.updateDisplayName(
            "${appleCredential.givenName} ${appleCredential.familyName}");
      }

      return userCredential.user;
    } catch (e) {
      print('Erro no login com Apple: $e');
      rethrow;
    }
  }

  // Obter usuário atual
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Logout
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut(); // Desconectar do Google
      return await _auth.signOut(); // Desconectar do Firebase
    } catch (e) {
      print('Erro no logout: $e');
      rethrow;
    }
  }
}