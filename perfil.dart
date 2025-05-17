import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';


class ProfilePage extends StatefulWidget {
  final Function? onSignOut;
  
  const ProfilePage({super.key, this.onSignOut});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Controladores para os campos de autenticação
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // Controladores para os dados do perfil
  final TextEditingController _alturaController = TextEditingController();
  final TextEditingController _pesoController = TextEditingController();
  final TextEditingController _idadeController = TextEditingController();
  final TextEditingController _metaPassosController = TextEditingController();
  
  bool _isLoading = false;
  bool _isLoggedIn = false;
  String _userId = "";
  String _errorMessage = "";
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
  }
  Future<void> _scanForDevices() async {
  setState(() {
    _isScanning = true;
    _devices.clear();
  });
  
  try {
    FlutterBluetoothSerial bluetooth = FlutterBluetoothSerial.instance;
    bool? isEnabled = await bluetooth.isEnabled;
    
    if (isEnabled != true) {
      await bluetooth.requestEnable();
    }
    
    List<BluetoothDevice> bondedDevices = await bluetooth.getBondedDevices();
    setState(() {
      _devices = bondedDevices;
      _isScanning = false;
    });
  } catch (e) {
    print('Erro ao escanear dispositivos: $e');
    setState(() {
      _isScanning = false;
    });
  }
}

// ignore: unused_element
Future<void> _saveSelectedDevice(String address) async {
  try {
    await _firestore.collection('users').doc(_userId).update({
      'deviceAddress': address,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    // Armazenar localmente para uso imediato
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('deviceAddress', address);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dispositivo salvo com sucesso!'),
        backgroundColor: Colors.black,
      ),
    );
  } catch (e) {
    setState(() {
      _errorMessage = "Erro ao salvar dispositivo: ${e.toString()}";
    });
  }
}

  void _checkCurrentUser() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _isLoggedIn = true;
        _userId = user.uid;
      });
      _loadUserData();
    }
  }

  void _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final userData = await _firestore.collection('users').doc(_userId).get();
      if (userData.exists) {
        final data = userData.data();
        setState(() {
          _alturaController.text = data?['altura']?.toString() ?? '';
          _pesoController.text = data?['peso']?.toString() ?? '';
          _idadeController.text = data?['idade']?.toString() ?? '';
          _metaPassosController.text = data?['metaPassos']?.toString() ?? ''; // Valor padrão de 10000
        });
      }
    } catch (e) {
      print('Erro ao carregar dados: $e');
      setState(() {
        _errorMessage = "Erro ao carregar dados: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      
      if (userCredential.user != null) {
        setState(() {
          _isLoggedIn = true;
          _userId = userCredential.user!.uid;
        });
        _loadUserData();
     }
    } on FirebaseAuthException catch (e) {
      String errorMsg;
      
      // Traduzir mensagens de erro comuns para o português
      switch (e.code) {
        case 'user-not-found':
          errorMsg = "Usuário não encontrado. Verifique seu email.";
          break;
        case 'wrong-password':
          errorMsg = "Senha incorreta. Tente novamente.";
          break;
        case 'invalid-email':
          errorMsg = "Email inválido. Verifique o formato.";
          break;
        default:
          errorMsg = "Falha ao fazer login: ${e.message}";
      }
      
      setState(() {
        _errorMessage = errorMsg;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Falha ao fazer login: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSignUp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      
      if (userCredential.user != null) {
        setState(() {
          _isLoggedIn = true;
          _userId = userCredential.user!.uid;
        });
        
        // Inicializar o documento do usuário no Firestore
        await _firestore.collection('users').doc(_userId).set({
          'email': _emailController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Falha ao criar conta: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      // Validar e converter a meta de passos
      final metaPassos = int.tryParse(_metaPassosController.text);
      if (metaPassos == null || metaPassos <= 0) {
        throw Exception('A meta de passos deve ser um número positivo');
      }

      // Validar outros campos
      final altura = double.tryParse(_alturaController.text);
      final peso = double.tryParse(_pesoController.text);
      final idade = int.tryParse(_idadeController.text);

      if (altura == null || altura <= 0) {
        throw Exception('A altura deve ser um número positivo');
      }
      if (peso == null || peso <= 0) {
        throw Exception('O peso deve ser um número positivo');
      }
      if (idade == null || idade <= 0) {
        throw Exception('A idade deve ser um número positivo');
      }

      // Atualizar dados no Firestore
      await _firestore.collection('users').doc(_userId).update({
        'altura': altura,
        'peso': peso,
        'idade': idade,
        'metaPassos': metaPassos,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dados salvos com sucesso!'),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = "Erro ao salvar dados: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _logout() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _auth.signOut();
      setState(() {
        _isLoggedIn = false;
        _userId = "";
        _emailController.clear();
        _passwordController.clear();
        _alturaController.clear();
        _pesoController.clear();
        _idadeController.clear();
        _metaPassosController.clear();
      });
      
      if (widget.onSignOut != null) {
        widget.onSignOut!();
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Erro ao fazer logout: ${e.toString()}";
      });
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
        title: const Text('Perfil'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: _isLoggedIn
            ? [
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: _logout,
                ),
              ]
            : null,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.black,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: _isLoggedIn ? _buildProfileForm() : _buildAuthForm(),
            ),
    );
  }

  Widget _buildAuthForm() {
    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Icon(
            FontAwesomeIcons.userCircle,
            size: 80,
            color: Colors.black54,
          ),
          const SizedBox(height: 20),
          const Text(
            'Faça login ou crie uma conta para continuar',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 30),
          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(FontAwesomeIcons.envelope, size: 18),
              contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Senha',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(FontAwesomeIcons.lock, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _isPasswordVisible = !_isPasswordVisible;
                  });
                },
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
            ),
            obscureText: !_isPasswordVisible,
          ),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('Entrar'),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _isLoading ? null : _handleSignUp,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.black),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Criar Conta', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileForm() {
  return Container(
    padding: const EdgeInsets.all(20),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              FontAwesomeIcons.userCircle,
              size: 24,
              color: Colors.black,
            ),
            const SizedBox(width: 10),
            Text(
              'Seus Dados Pessoais',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Informe seus dados para personalizar sua experiência',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 25),

        // Altura
        _buildProfileField(
          controller: _alturaController,
          label: 'Altura (m)',
          hint: 'Ex: 1.75',
          icon: FontAwesomeIcons.rulerVertical,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Peso
        _buildProfileField(
          controller: _pesoController,
          label: 'Peso (kg)',
          hint: 'Ex: 70',
          icon: FontAwesomeIcons.weightScale,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Idade
        _buildProfileField(
          controller: _idadeController,
          label: 'Idade',
          hint: 'Ex: 30',
          icon: FontAwesomeIcons.cakeCandles,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),

        // Meta de Passos
        _buildProfileField(
          controller: _metaPassosController,
          label: 'Meta de Passos Diários',
          hint: 'Ex: 10000',
          icon: FontAwesomeIcons.shoePrints,
          keyboardType: TextInputType.number,
        ),

        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 30),

        ElevatedButton(
          onPressed: _isLoading ? null : _saveUserData,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Salvar'),
        ),

        const SizedBox(height: 30),

        // --- Parte do Bluetooth ---
        Row(
          children: [
            const Icon(
              FontAwesomeIcons.bluetooth,
              size: 24,
              color: Colors.black,
            ),
            const SizedBox(width: 10),
            Text(
              'Conectar ao StepStalk',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          'Conecte ao seu contador de passos',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),

        ElevatedButton.icon(
          onPressed: _isScanning ? null : _scanForDevices,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(FontAwesomeIcons.search),
          label: Text(_isScanning ? 'Procurando...' : 'Procurar dispositivos'),
        ),
        const SizedBox(height: 12),

        if (_devices.isNotEmpty)
          ..._devices.map(
            (device) => ListTile(
              title: Text(device.name ?? 'Dispositivo desconhecido'),
              subtitle: Text(device.address),
              trailing: ElevatedButton(
                onPressed: () => _saveSelectedDevice(device.address),
                child: const Text('Conectar'),
              ),
            ),
          ),
      ],
    ),
  );
}


  Widget _buildProfileField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: Icon(icon, size: 18),
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      ),
      keyboardType: keyboardType,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _alturaController.dispose();
    _pesoController.dispose();
    _idadeController.dispose();
    _metaPassosController.dispose();
    super.dispose();
  }
}