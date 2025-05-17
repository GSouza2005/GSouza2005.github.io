import 'package:url_launcher/url_launcher.dart'
    show LaunchMode, canLaunchUrl, launchUrl;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'perfil.dart';
import 'dart:async';
import 'desafio.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'services/activity_service.dart';

// Variáveis reais que serão atualizadas com dados do sensor
int realSteps = 0;
double realDistance = 0.0;
int realCalories = 0;
String realActiveTime = "0h 0m";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const StepStalk());
}
int _parseToInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _parseToDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}


class StepStalk extends StatelessWidget {
  const StepStalk({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StepStalk',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: const StepStalkApp(),
    );
  }
}

class StepStalkApp extends StatefulWidget {
  const StepStalkApp({super.key});

  @override
  State<StepStalkApp> createState() => _StepStalkAppState();
}

class _StepStalkAppState extends State<StepStalkApp> {
 final ActivityService _activityService = ActivityService(); 
  // Adicione como propriedades da classe _StepStalkAppState
  BluetoothConnection? connection;
  bool isConnected = false;
  String deviceAddress = ""; // Endereço MAC do seu ESP32
  Timer? dataUpdateTimer;
  bool isConnecting = false;
  bool _isUserLoggedIn = false;
  String _userId = "";
  int streak = 0;

  // Método para inicializar a conexão Bluetooth
  Future<void> initBluetooth() async {
    // Verificar permissões do Bluetooth
    FlutterBluetoothSerial bluetooth = FlutterBluetoothSerial.instance;
    bool? isEnabled = await bluetooth.isEnabled;

    if (isEnabled != true) {
      // Solicitar ao usuário para ativar o Bluetooth
      await bluetooth.requestEnable();
    }

    // Se temos um endereço de dispositivo salvo, tentamos conectar
    if (deviceAddress.isNotEmpty) {
      connectToDevice(deviceAddress);
    }
  }

  // Método para conectar ao dispositivo ESP32
Future<void> connectToDevice(String address) async {
  if (isConnecting) return;

  setState(() {
    isConnecting = true;
  });

  try {
    print('Tentando conectar ao dispositivo: $address');
    connection = await BluetoothConnection.toAddress(address);
    print('Conectado ao dispositivo');

    setState(() {
      isConnected = true;
      isConnecting = false;
      deviceAddress = address; // Salva endereço para reconexões futuras
    });

    // Configurar listener para dados recebidos
    connection!.input!
        .listen((Uint8List data) {
          String dataString = utf8.decode(data);
          print('Dados recebidos: $dataString');
          processReceivedData(dataString);
        })
        .onDone(() {
          setState(() {
            isConnected = false;
          });
          print('Desconectado');
          
          // Tenta reconectar após desconexão
          Future.delayed(Duration(seconds: 3), () {
            if (!isConnected && !isConnecting) {
              connectToDevice(deviceAddress);
            }
          });
        });

    // Iniciar timer para solicitar dados a cada 5 segundos
    dataUpdateTimer?.cancel(); // Cancela timer anterior se existir
    dataUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      requestDataFromESP32();
    });
    
    // Solicita dados imediatamente após conectar
    requestDataFromESP32();
  } catch (e) {
    print('Erro ao conectar: $e');
    setState(() {
      isConnecting = false;
    });
    
    // Tenta reconectar após erro
    Future.delayed(Duration(seconds: 5), () {
      if (!isConnected && !isConnecting) {
        connectToDevice(address);
      }
    });
  }
}
Future<void> scanAndConnectToDevice() async {
  // Este método pode ser chamado de um botão na interface
  setState(() {
    isConnecting = true;
  });
  
  try {
    // Substitua pelo endereço MAC do seu ESP32
    String esp32Address = "XX:XX:XX:XX:XX:XX"; 
    
    await connectToDevice(esp32Address);
  } catch (e) {
    print('Erro ao escanear/conectar: $e');
    setState(() {
      isConnecting = false;
    });
  }
}

  // Enviar solicitação de dados para o ESP32
 void requestDataFromESP32() {
  if (connection?.isConnected == true) {
    try {
      connection!.output.add(utf8.encode('DATA\r\n'));
      connection!.output.allSent.then((_) {
        print('Solicitação de dados enviada ao ESP32');
      });
    } catch (e) {
      print('Erro ao solicitar dados: $e');
    }
  }
}

  // Processar dados recebidos do ESP32
  void processReceivedData(String data) {
  try {
    print('Dados recebidos: $data');
    Map<String, dynamic> parsedData = {};

    data.split(';').forEach((item) {
      List<String> keyValue = item.split(':');
      if (keyValue.length == 2) {
        String key = keyValue[0].trim();
        String value = keyValue[1].trim();

        switch (key) {
          case 'STEPS':
            parsedData['steps'] = int.tryParse(value) ?? 0;
            break;
          case 'DISTANCE':
            parsedData['distance'] = double.tryParse(value) ?? 0.0;
            break;
          case 'CALORIES':
            parsedData['calories'] = int.tryParse(value) ?? 0;
            break;
          case 'ACTIVETIME':
            parsedData['activeTime'] = value;
            break;
        }
      }
    });

    // Atualizar valores locais
    updateStepsData(parsedData);

    // Sincronizar com Firebase se estiver logado
     if (_userId.isNotEmpty) {
        _activityService.updateActivityData(parsedData);
      }
  } catch (e) {
    print('Erro ao processar dados: $e');
  }
}

  // Atualizar valores locais
  void updateStepsData(Map<String, dynamic> data) {
  setState(() {
    if (data.containsKey('steps')) {
      steps = data['steps'];
      realSteps = steps; // Atualizar variável global
     // Atualizar o dado de hoje no gráfico semanal (índice 6 = hoje)
      if (chartData['week']!.length > 6) {
        chartData['week']![6] = steps.toDouble();
      }
      
      // Atualizar o dado de hoje no gráfico mensal
      DateTime now = DateTime.now();
      int dayOfMonth = now.day - 1; // Arrays começam em 0
      if (dayOfMonth >= 0 && dayOfMonth < chartData['month']!.length) {
        chartData['month']![dayOfMonth] = steps.toDouble();
      }
    }

    if (data.containsKey('distance')) {
      distance = data['distance'];
      realDistance = distance; // Atualizar variável global
    }
    if (data.containsKey('calories')) {
      calories = data['calories'];
      realCalories = calories; // Atualizar variável global
    }
    if (data.containsKey('activeTime')) {
      activeTime = data['activeTime'];
      realActiveTime = activeTime; // Atualizar variável global
    }
  });
}

  // Sincronizar dados com Firebase
  Future<void> syncDataWithFirebase(Map<String, dynamic> data) async {
    try {
      // Obter data atual para registrar atividade
      DateTime now = DateTime.now();
      String dateKey =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      // Referência do documento do dia atual
      DocumentReference dailyRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('activity')
          .doc(dateKey);

      // Verificar se já existe documento para hoje
      DocumentSnapshot dailySnapshot = await dailyRef.get();

      if (dailySnapshot.exists) {
        // Atualizar documento existente
        await dailyRef.update({
          'steps': data['steps'],
          'distance': data['distance'],
          'calories': data['calories'],
          'activeTime': data['activeTime'],
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        // Criar novo documento
        await dailyRef.set({
          'steps': data['steps'],
          'distance': data['distance'],
          'calories': data['calories'],
          'activeTime': data['activeTime'],
          'date': dateKey,
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

       // Atualizar totais mensais
    await updateMonthlyStats();
    
    // Recarregar os gráficos para mostrar dados atualizados
    _loadWeeklyActivityChart();
    _loadMonthlyActivityChart();
    } catch (e) {
      print('Erro ao sincronizar com Firebase: $e');
    }
  }

  // Atualizar estatísticas mensais
  Future<void> updateMonthlyStats() async {
    try {
      DateTime now = DateTime.now();
      String monthKey = "${now.year}-${now.month.toString().padLeft(2, '0')}";

      // Buscar todos os registros do mês atual
      QuerySnapshot monthDocs =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_userId)
              .collection('activity')
              .where('date', isGreaterThanOrEqualTo: "$monthKey-01")
              .where('date', isLessThanOrEqualTo: "$monthKey-31")
              .get();

      // Calcular totais
      List<double> dailySteps = [];
      int totalSteps = 0;
      double totalDistance = 0;
      int totalCalories = 0;

      for (var doc in monthDocs.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        totalSteps += _parseToInt(data['steps']);
        totalDistance += _parseToDouble(data['distance']);
        totalCalories += _parseToInt(data['calories']);
        dailySteps.add(_parseToInt(data['steps']).toDouble());
      }

      // Atualizar dados do gráfico mensal
      setState(() {
        chartData['month'] = dailySteps;
      });

      // Salvar resumo mensal no Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('monthly_summary')
          .doc(monthKey)
          .set({
            'totalSteps': totalSteps,
            'totalDistance': totalDistance,
            'totalCalories': totalCalories,
            'daysActive': monthDocs.docs.length,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Erro ao atualizar estatísticas mensais: $e');
    }
  }

  // Valores serão atualizados pelo ESP32
  int steps = 0; // Será substituído por realSteps
  int dailyGoal = 0; // Agora será atualizado com valor do perfil do usuário
  
  String selectedView = 'week';
  bool showShareModal = false;
  StreamSubscription? _userDataSubscription;

  // Valores calculados para métricas - Inicializados com 0
  double distance = 0.0; // Em km - Será atualizado com dados do ESP32
  int calories = 0; // Será atualizado com dados do ESP32
  String activeTime = "0h 0m"; // Será atualizado com dados do ESP32

  final Map<String, List<double>> chartData = {
    'week': List.filled(7, 0.0),
    'month': List.filled(31, 0.0),
  };

  // Novo método para carregar dados do gráfico mensal
Future<void> _loadMonthlyActivityChart() async {
  try {
    // Calcular o primeiro dia do mês atual
    DateTime now = DateTime.now();
    DateTime monthStart = DateTime(now.year, now.month, 1);
    
    // Criar um array com 31 dias, todos inicializados com 0
    List<double> monthData = List.filled(31, 0.0);
    
    // Buscar atividades do mês
    if (_userId.isNotEmpty) {
      QuerySnapshot monthDocs = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('activity')
          .where(
            'date',
            isGreaterThanOrEqualTo:
                "${monthStart.year}-${monthStart.month.toString().padLeft(2, '0')}-01",
          )
          .where(
            'date',
            isLessThanOrEqualTo:
                "${monthStart.year}-${monthStart.month.toString().padLeft(2, '0')}-31",
          )
          .get();
      
      // Preencher array com dados disponíveis
      for (var doc in monthDocs.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String dateStr = data['date'];
        if (dateStr != null) {
          DateTime docDate = DateTime.parse(dateStr);
          
          // O índice será o dia do mês - 1 (pois arrays começam em 0)
          int index = docDate.day - 1;
          if (index >= 0 && index < 31) {
            monthData[index] = (data['steps'] ?? 0).toDouble();
          }
        }
      }
      
      setState(() {
        chartData['month'] = monthData;
      });
    }
  } catch (e) {
    print('Erro ao carregar gráfico mensal: $e');
  }
}

  @override
void initState() {
  super.initState();
  
  // Inicialize com array vazio (sem dados aleatórios)
  chartData['week'] = List.filled(7, 0.0);
  chartData['month'] = List.filled(31, 0.0);
  
  // Verificar se o usuário está logado ao iniciar o app
  _checkCurrentUser();
  
  // Inicializar Bluetooth e tentar conectar automaticamente
  initBluetooth();
  
  // Carregar dados da atividade de hoje
  _loadTodayActivity();
  
  // Adicione este método para carregar dados mensais
  _loadMonthlyActivityChart();
}

  @override
  void dispose() {
    // Cancelar timer
    dataUpdateTimer?.cancel();
    // Fechar conexão Bluetooth
    connection?.dispose();
    // Cancelar a inscrição no stream ao descartar o widget
    _userDataSubscription?.cancel();
    super.dispose();
  }

  void _checkCurrentUser() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _isUserLoggedIn = true;
        _userId = user.uid;
      });
      // Carregar dados do usuário do Firestore
      _loadUserData();
    }
  }

  // Método para atualizar a meta de passos
  void _updateDailyGoal(int newGoal) {
    setState(() {
      dailyGoal = newGoal;
      print('Meta de passos atualizada para: $dailyGoal');
    });
  }

  void _loadUserData() {
    // Cancelar qualquer inscrição anterior
    _userDataSubscription?.cancel();

    // Inscrever-se para receber atualizações em tempo real dos dados do usuário
    _userDataSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .snapshots()
        .listen(
          (documentSnapshot) {
            if (documentSnapshot.exists) {
              final userData = documentSnapshot.data();
              if (userData != null) {
                  // Atualizar a meta diária com o valor do Firestore
                _updateDailyGoal(_parseToInt(userData['metaPassos']));

                setState(() {
                  // Atualizar outras métricas conforme necessário
                  distance = calculateDistanceFromSteps(steps);
                  calories = calculateCaloriesFromSteps(steps);
                  activeTime = calculateActiveTime();
                });

                _loadTodayActivity();
              }
            }
          },
          onError: (error) {
            print('Erro ao carregar dados: $error');
          },
        );
  }

  // Novo método para carregar dados de atividade do dia atual
  Future<void> _loadTodayActivity() async {
    try {
      // Obter data atual
      DateTime now = DateTime.now();
      String dateKey =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      // Buscar documento do dia atual
      DocumentSnapshot activityDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_userId)
              .collection('activity')
              .doc(dateKey)
              .get();

      if (activityDoc.exists) {
        Map<String, dynamic> data = activityDoc.data() as Map<String, dynamic>;

        setState(() {
          steps = data['steps'] ?? 0;
          distance = data['distance'] ?? 0.0;
          calories = data['calories'] ?? 0;
          activeTime = data['activeTime'] ?? "0h 0m";

          // Atualizar variáveis globais
          realSteps = steps;
          realDistance = distance;
          realCalories = calories;
          realActiveTime = activeTime;
        });
      } else {
        // Se não houver dados para hoje, zerar os contadores
        setState(() {
          steps = 0;
          distance = 0.0;
          calories = 0;
          activeTime = "0h 0m";

          // Atualizar variáveis globais
          realSteps = 0;
          realDistance = 0.0;
          realCalories = 0;
          realActiveTime = "0h 0m";
        });
      }

      // Carregar dados para o gráfico semanal
      _loadWeeklyActivityChart();
    } catch (e) {
      print('Erro ao carregar atividade diária: $e');
      // Em caso de erro, zerar os contadores
      setState(() {
        steps = 0;
        distance = 0.0;
        calories = 0;
        activeTime = "0h 0m";

        // Atualizar variáveis globais
        realSteps = 0;
        realDistance = 0.0;
        realCalories = 0;
        realActiveTime = "0h 0m";
      });
    }
  }

  // Novo método para carregar dados do gráfico semanal
  Future<void> _loadWeeklyActivityChart() async {
    try {
      // Calcular intervalo da semana (últimos 7 dias)
      DateTime now = DateTime.now();
      DateTime weekStart = now.subtract(Duration(days: 6));

      List<double> weekData = List.filled(7, 0.0);

      // Buscar atividades da semana
      QuerySnapshot weekDocs =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_userId)
              .collection('activity')
              .where(
                'date',
                isGreaterThanOrEqualTo:
                    "${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}",
              )
              .where(
                'date',
                isLessThanOrEqualTo:
                    "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
              )
              .get();

      // Preencher array com dados disponíveis
      for (var doc in weekDocs.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String dateStr = data['date'];
        DateTime docDate = DateTime.parse(dateStr);

        // Calcular índice (0 = 6 dias atrás, 6 = hoje)
        int dayDiff = now.difference(docDate).inDays;
        if (dayDiff >= 0 && dayDiff < 7) {
          int index =
              6 - dayDiff; // Inverter para colocar dia mais antigo primeiro
          weekData[index] = (data['steps'] ?? 0).toDouble();
        }
      }

      setState(() {
        chartData['week'] = weekData;
      });
    } catch (e) {
      print('Erro ao carregar gráfico semanal: $e');
    }
  }

  // Funções de cálculo
  double calculateDistanceFromSteps(int steps) {
    // Média de 0.0007 km por passo
    return steps * 0.0007;
  }

  int calculateCaloriesFromSteps(int steps) {
    // Média de 0.04 calorias por passo
    return (steps * 0.04).round();
  }

  String calculateActiveTime() {
    // Estimativa de 1 hora para cada 5000 passos
    int hours = steps ~/ 5000;
    int minutes = ((steps % 5000) / 83.33).round(); // 5000/60 = 83.33 passos por minuto
    return "${hours}h ${minutes}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 80.0), // Adiciona padding para a navegação
                child: Column(
                  children: [
                    const SizedBox(height: 64), // Space for fixed header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          // Main Progress Card
                          _buildProgressCard(),
                          const SizedBox(height: 16),
                          // Metrics Cards
                          _buildMetricsCards(),
                          const SizedBox(height: 16),
                          // Progress Chart
                          _buildProgressChart(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Fixed Header
          _buildHeader(),
          // Bottom Navigation
          _buildBottomNavigation(),
          // Share Modal
          if (showShareModal) _buildShareModal(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(FontAwesomeIcons.shoePrints, color: Colors.black),
                const SizedBox(width: 8),
                const Text(
                  'StepStalk',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.black),
              onPressed: () {
                setState(() {
                  showShareModal = true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    steps.toString(),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'passos hoje',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black.withOpacity(0.2),
                    width: 4,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(dailyGoal > 0 ? ((steps / dailyGoal) * 100).round() : 0)}%', // Usa o dailyGoal atualizado
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      // NOVO: Mostra a meta atual para referência do usuário
                      Text(
                        'Meta: $dailyGoal',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(FontAwesomeIcons.fire, color: Colors.black, size: 16),
              const SizedBox(width: 8),
              Text(
                'Sequência de $streak dias!',
                style: const TextStyle(fontSize: 14, color: Colors.black),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // termina aqui

  Widget _buildMetricsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            icon: FontAwesomeIcons.road,
            value:
                '${distance.toStringAsFixed(1)} km', // Formatação para uma casa decimal
            label: 'Distância',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            icon: FontAwesomeIcons.fire,
            value: calories.toString(),
            label: 'Calorias',
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            icon: FontAwesomeIcons.clock,
            value: activeTime,
            label: 'Tempo',
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
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
        children: [
          Icon(icon, color: Colors.black),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildProgressChart() {
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progresso',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              Row(
                children: [
                  _buildViewToggleButton('week', 'Semana'),
                  const SizedBox(width: 8),
                  _buildViewToggleButton('month', 'Mês'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 12000,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        List<String> titles =
                            selectedView == 'week'
                                ? [
                                  'Seg',
                                  'Ter',
                                  'Qua',
                                  'Qui',
                                  'Sex',
                                  'Sáb',
                                  'Dom',
                                ]
                                : List.generate(
                                  30,
                                  (index) => (index + 1).toString(),
                                );

                        if (selectedView == 'month' && value % 5 != 0) {
                          return const SizedBox();
                        }

                        String title =
                            value.toInt() < titles.length
                                ? titles[value.toInt()]
                                : '';
                        return Text(
                          title,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _getBarGroups(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggleButton(String view, String label) {
    return InkWell(
      onTap: () {
        setState(() {
          selectedView = view;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selectedView == view ? Colors.black : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selectedView == view ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _getBarGroups() {
    List<double> data = chartData[selectedView]!;
    return List.generate(
      data.length,
      (index) => BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: data[index],
            color: Colors.black,
            width: selectedView == 'week' ? 20 : 8,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(FontAwesomeIcons.house),
              onPressed: () {
                // Já está na tela inicial
              },
            ),
            IconButton(
              icon: const Icon(FontAwesomeIcons.flag),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DesafioPage(
                      steps: steps,
                      distance: distance,
                      calories: calories,
                      dailyGoal: dailyGoal,
                        ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(FontAwesomeIcons.person),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ProfilePage(
                          onSignOut: () {
                            setState(() {
                              _isUserLoggedIn = false;
                              _userId = "";
                          dailyGoal = 10000;
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareModal() {
    return GestureDetector(
      onTap: () {
        setState(() {
          showShareModal = false;
        });
      },
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Compartilhar seu Progresso',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(
                        FontAwesomeIcons.facebook,
                        color: Colors.blue,
                        size: 32,
                      ),
                      onPressed: () async {
                        final Uri url = Uri.parse('https://www.facebook.com/');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } else {
                          throw 'Não foi possível abrir o link';
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(
                        FontAwesomeIcons.instagram,
                        color: Colors.pink,
                        size: 32,
                      ),
                      onPressed: () async {
                        final Uri url = Uri.parse('https://www.instagram.com/');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } else {
                          throw 'Não foi possível abrir o link';
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(
                        FontAwesomeIcons.xTwitter,
                        color: Colors.black,
                        size: 32,
                      ),
                      onPressed: () async {
                        final Uri url = Uri.parse('https://twitter.com/');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          );
                        } else {
                          throw 'Não foi possível abrir o link';
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      showShareModal = false;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    foregroundColor: Colors.grey[600],
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
