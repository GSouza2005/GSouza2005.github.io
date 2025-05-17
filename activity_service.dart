import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ActivityService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream para atualizações em tempo real dos dados de atividade
  Stream<Map<String, dynamic>> getActivityStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value({});

    final now = DateTime.now();
    final dateKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('activity')
        .doc(dateKey)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return {};
      return snapshot.data() ?? {};
    });
  }

  // Método para atualizar dados de atividade
  Future<void> updateActivityData(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final dateKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final docRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('activity')
        .doc(dateKey);

    final doc = await docRef.get();
    if (doc.exists) {
      await docRef.update({
        ...data,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } else {
      await docRef.set({
        ...data,
        'date': dateKey,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    }

    // Atualizar totais mensais
    await _updateMonthlyStats(user.uid, data);
  }

  // Método para atualizar estatísticas mensais
  Future<void> _updateMonthlyStats(String userId, Map<String, dynamic> data) async {
    final now = DateTime.now();
    final monthKey = "${now.year}-${now.month.toString().padLeft(2, '0')}";

    final monthRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('monthly_summary')
        .doc(monthKey);

    final monthDoc = await monthRef.get();
    if (monthDoc.exists) {
      final currentData = monthDoc.data() ?? {};
      await monthRef.update({
        'totalSteps': (currentData['totalSteps'] ?? 0) + (data['steps'] ?? 0),
        'totalDistance': (currentData['totalDistance'] ?? 0) + (data['distance'] ?? 0),
        'totalCalories': (currentData['totalCalories'] ?? 0) + (data['calories'] ?? 0),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await monthRef.set({
        'totalSteps': data['steps'] ?? 0,
        'totalDistance': data['distance'] ?? 0,
        'totalCalories': data['calories'] ?? 0,
        'daysActive': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Método para obter estatísticas mensais
  Future<Map<String, dynamic>> getMonthlyStats() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    final now = DateTime.now();
    final monthKey = "${now.year}-${now.month.toString().padLeft(2, '0')}";

    final monthDoc = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('monthly_summary')
        .doc(monthKey)
        .get();

    return monthDoc.data() ?? {};
  }
} 