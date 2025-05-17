import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Método para salvar os passos
  Future<void> salvarPassos(int passos) async {
    try {
      await _db.collection('passos').add({
        'quantidade': passos,
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('Passos salvos no Firestore!');
    } catch (e) {
      print('Erro ao salvar passos: $e');
    }
  }

  // Método para recuperar os passos em tempo real
  Stream<List<int>> getPassos() {
    return _db.collection('passos')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc['quantidade'] as int).toList();
    });
  }
}
