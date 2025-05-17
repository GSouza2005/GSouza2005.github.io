import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'services/activity_service.dart';
import 'dart:async';

class DesafioPage extends StatefulWidget {
  final int steps;
  final double distance;
  final int calories;
  final int dailyGoal;

   const DesafioPage({
    super.key, 
    required this.steps,
    required this.distance,
    required this.calories,
    required this.dailyGoal,
  });

  @override
  _DesafioPageState createState() => _DesafioPageState();
}

class _DesafioPageState extends State<DesafioPage> {
  final ActivityService _activityService = ActivityService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  String _userId = "";
  int _totalSteps = 0;
  int _dailyGoal = 0;
  double _totalDistanceKm = 0.0;
  int _totalCalories = 0;
  StreamSubscription<Map<String, dynamic>>? _activitySubscription;
  
  // Lista de marcos geográficos ordenados por distância
  final List<Map<String, dynamic>> _landmarks = [
    {
      'name': 'Volta da Praça do Comércio',
      'distance': 1,
      'description': 'Você completou uma volta na icônica Praça do Comércio em Lisboa!',
      'icon': FontAwesomeIcons.monument,
      'unlocked': false,
    },
    {
      'name': 'Percurso da Ponte 25 de Abril',
      'distance': 5,
      'description': 'Você caminhou o equivalente à travessia da Ponte 25 de Abril!',
      'icon': FontAwesomeIcons.bridge,
      'unlocked': false,
    },
    {
      'name': 'Lisboa - Sintra',
      'distance': 25,
      'description': 'Parabéns! Você percorreu a distância de Lisboa até Sintra!',
      'icon': FontAwesomeIcons.mountain,
      'unlocked': false,
    },
    {
      'name': 'Lisboa - Setúbal',
      'distance': 50,
      'description': 'Impressionante! Você caminhou de Lisboa até Setúbal!',
      'icon': FontAwesomeIcons.ship,
      'unlocked': false,
    },
    {
      'name': 'Lisboa - Évora',
      'distance': 130,
      'description': 'Incrível! Sua jornada equivale a ir de Lisboa até Évora!',
      'icon': FontAwesomeIcons.tree,
      'unlocked': false,
    },
    {
      'name': 'Fronteira com Espanha',
      'distance': 200,
      'description': 'Uau! Você caminhou até a fronteira de Portugal com Espanha!',
      'icon': FontAwesomeIcons.flagCheckered,
      'unlocked': false,
    },
    {
      'name': 'Lisboa - Madrid',
      'distance': 625,
      'description': 'Extraordinário! Você percorreu a distância de Lisboa até Madrid!',
      'icon': FontAwesomeIcons.city,
      'unlocked': false,
    },
    {
      'name': 'Atravessou a Península Ibérica',
      'distance': 1200,
      'description': 'Inacreditável! Você atravessou toda a Península Ibérica!',
      'icon': FontAwesomeIcons.earthEurope,
      'unlocked': false,
    },
  ];
  
  // Lista de desafios mensais
  final List<Map<String, dynamic>> _monthlyGoals = [
    {
      'title': 'Passo a Passo',
      'goal': 150000,
      'reward': '150 pontos',
      'description': 'Alcance 150.000 passos este mês',
      'icon': FontAwesomeIcons.personWalking,
    },
    {
      'title': 'Queimando Calorias',
      'goal': 15000,
      'reward': '200 pontos',
      'description': 'Queime 15.000 calorias este mês',
      'icon': FontAwesomeIcons.fire,
    },
    {
      'title': 'Maratonista',
      'goal': 100,
      'reward': '250 pontos',
      'description': 'Caminhe 100 km este mês',
      'icon': FontAwesomeIcons.road,
    },
  ];
  
  // Próximo marco a ser alcançado
  Map<String, dynamic>? _nextLandmark;
  
  // Progresso dos desafios mensais
  final List<double> _monthlyProgress = [0, 0, 0];

  @override
  void initState() {
    super.initState();
    // Inicializar com os valores passados pelo construtor
    _totalSteps = widget.steps;
    _totalDistanceKm = widget.distance;
    _totalCalories = widget.calories;
    _dailyGoal = widget.dailyGoal;
    _checkCurrentUser();
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();
    super.dispose();
  }

  void _checkCurrentUser() {
    final User? user = _auth.currentUser;
    if (user != null) {
      setState(() {
        _userId = user.uid;
      });
      _loadUserData();
      _setupActivityStream();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setupActivityStream() {
    _activitySubscription?.cancel();
    _activitySubscription = _activityService.getActivityStream().listen((data) {
      if (data.isNotEmpty) {
        setState(() {
          _totalSteps = data['steps'] ?? 0;
          _totalDistanceKm = data['distance'] ?? 0.0;
          _totalCalories = data['calories'] ?? 0;
          
          // Atualizar status de marcos geográficos desbloqueados
          for (var landmark in _landmarks) {
            landmark['unlocked'] = _totalDistanceKm >= landmark['distance'];
          }
          
          // Encontrar próximo marco
          _nextLandmark = _landmarks.firstWhere(
            (landmark) => !landmark['unlocked'],
            orElse: () => _landmarks.last,
          );
        });
      }
    });
  }

  void _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Carregar dados do usuário
      final userData = await _firestore.collection('users').doc(_userId).get();
      if (userData.exists) {
        final data = userData.data();
        setState(() {
          _dailyGoal = data?['metaPassos'] ?? 10000;
        });
      }
      
      // Carregar estatísticas mensais
      final monthlyStats = await _activityService.getMonthlyStats();
      setState(() {
        _monthlyProgress[0] = (monthlyStats['totalSteps'] ?? 0) / _monthlyGoals[0]['goal'];
        _monthlyProgress[1] = (monthlyStats['totalCalories'] ?? 0) / _monthlyGoals[1]['goal'];
        _monthlyProgress[2] = (monthlyStats['totalDistance'] ?? 0) / _monthlyGoals[2]['goal'];
      });
    } catch (e) {
      print('Erro ao carregar dados: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desafios'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.black,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatisticsCard(),
                  const SizedBox(height: 24),
                  _buildJourneyMap(),
                  const SizedBox(height: 24),
                  _buildMonthlyGoals(),
                  const SizedBox(height: 80), // Espaço para navegação inferior
                ],
              ),
            ),
    );
  }

  Widget _buildStatisticsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  FontAwesomeIcons.trophy,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Progresso Total',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Veja o quanto já conquistou!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  FontAwesomeIcons.shoePrints,
                  _totalSteps.toString(),
                  'Passos Totais',
                ),
              ),
              Expanded(
                child: _buildStatCard(
                  FontAwesomeIcons.road,
                  '${_totalDistanceKm.toStringAsFixed(1)} km',
                  'Distância Total',
                ),
              ),
              Expanded(
                child: _buildStatCard(
                  FontAwesomeIcons.fire,
                  _totalCalories.toString(),
                  'Calorias',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.black),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildJourneyMap() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  FontAwesomeIcons.map,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sua Caminhada',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Quão longe já foi',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Próximo Marco
          if (_nextLandmark != null) ...[
            Text(
              'Próximo Marco: ${_nextLandmark!['name']}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
                LinearPercentIndicator(
                lineHeight: 12.0,
                percent: min(_totalDistanceKm / _nextLandmark!['distance'], 1.0),
                backgroundColor: Colors.grey[200],
                progressColor: Colors.black,
                animation: true,
                animationDuration: 1500,
               barRadius: const Radius.circular(16),
               padding: EdgeInsets.zero,
   
  ),
            const SizedBox(height: 8),
            Text(
              '${_totalDistanceKm.toStringAsFixed(1)} km / ${_nextLandmark!['distance']} km',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            Text(
              'Faltam ${(_nextLandmark!['distance'] - _totalDistanceKm).toStringAsFixed(1)} km',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          
          const SizedBox(height: 24),
          const Text(
            'Marcos Desbloqueados',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          
          // Lista dos marcos
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _landmarks.length,
            itemBuilder: (context, index) {
              final landmark = _landmarks[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: landmark['unlocked'] 
                        ? Colors.grey[100] 
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: landmark['unlocked'] 
                          ? Colors.black
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: landmark['unlocked'] 
                            ? Colors.black.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        landmark['icon'],
                        color: landmark['unlocked'] ? Colors.black : Colors.grey,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      landmark['name'],
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: landmark['unlocked'] ? Colors.black : Colors.grey,
                      ),
                    ),
                    subtitle: Text(
                      landmark['unlocked'] 
                          ? landmark['description']
                          : '${landmark['distance']} km',
                      style: TextStyle(
                        color: landmark['unlocked'] ? Colors.grey[700] : Colors.grey,
                      ),
                    ),
                    trailing: landmark['unlocked']
                        ? const Icon(Icons.check_circle, color: Colors.black)
                        : Icon(Icons.lock, color: Colors.grey[400]),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyGoals() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  FontAwesomeIcons.calendarAlt,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Desafios do Mês',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Complete esses desafios até o final do mês',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Lista de desafios mensais
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _monthlyGoals.length,
            itemBuilder: (context, index) {
              final monthlyGoal = _monthlyGoals[index];
              final progress = _monthlyProgress[index];
              final completed = progress >= 1.0;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            monthlyGoal['icon'],
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            monthlyGoal['title'],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: completed 
                                ? Colors.black
                                : Colors.black.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            monthlyGoal['reward'],
                            style: TextStyle(
                              fontSize: 12,
                              color: completed ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      monthlyGoal['description'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearPercentIndicator(
                      lineHeight: 8.0,
                      percent: progress.clamp(0.0, 1.0),
                      backgroundColor: Colors.grey[200],
                      progressColor: completed ? Colors.green : Colors.black,
                      animation: true,
                      animationDuration: 1500,
                      barRadius: const Radius.circular(16),
                      padding: EdgeInsets.zero,
                      trailing: Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  double min(double a, double b) {
    return a < b ? a : b;
  }
}