import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'dart:html' as html;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("Firebase Error: $e");
  }
  runApp(const CarromApp());
}

class CarromApp extends StatelessWidget {
  const CarromApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const CarromScorePage(),
    );
  }
}

class GameRound {
  final Map<int, int> teamPoints;
  final Duration duration;
  GameRound(this.teamPoints, this.duration);

  Map<String, dynamic> toJson() => {
    'points': teamPoints.map((k, v) => MapEntry(k.toString(), v)),
    'durationMs': duration.inMilliseconds,
  };

  factory GameRound.fromJson(Map<String, dynamic> json) {
    var pts = json['points'] as Map;
    return GameRound(
      pts.map((k, v) => MapEntry(int.parse(k.toString()), v as int)),
      Duration(milliseconds: json['durationMs'] ?? 0),
    );
  }
}

class CarromScorePage extends StatefulWidget {
  const CarromScorePage({super.key});
  @override
  State<CarromScorePage> createState() => _CarromScorePageState();
}

class _CarromScorePageState extends State<CarromScorePage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  
  String? _gameId;
  int mode = 2;
  int targetScore = 25;
  bool gameStarted = false; // Initial IMMER false
  List<GameRound> rounds = [];
  
  final List<TextEditingController> scoreControllers = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> nameControllers = List.generate(3, (_) => TextEditingController());
  final TextEditingController _joinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkUrlForGame();
  }

  void _checkUrlForGame() {
    final String url = html.window.location.href;
    final Uri uri = Uri.parse(url);
    String? id = uri.queryParameters['id'];
    
    if (id == null && url.contains('id=')) {
      id = url.split('id=').last.split('&').first;
    }
    
    if (id != null && id.isNotEmpty) {
      _connectToGame(id.toUpperCase());
    }
  }

  void _connectToGame(String id) {
    _db.child('games/$id').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() {
          _gameId = id;
          mode = data['mode'] ?? 2;
          targetScore = data['target'] ?? 25;
          nameControllers[0].text = data['n0'] ?? "";
          nameControllers[1].text = data['n1'] ?? "";
          nameControllers[2].text = data['n2'] ?? "";
          
          if (data['rounds'] != null) {
            rounds = (data['rounds'] as List)
                .map((r) => GameRound.fromJson(Map<String, dynamic>.from(r)))
                .toList();
          } else {
            rounds = [];
          }
          gameStarted = true; // Hier wird umgeschaltet
        });
      }
    });
  }

  void _startNewCloudGame() {
    _gameId = "C-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    _updateCloud();
    _connectToGame(_gameId!);
  }

  void _updateCloud() {
    if (_gameId == null) return;
    _db.child('games/$_gameId').set({
      'mode': mode,
      'target': targetScore,
      'n0': nameControllers[0].text,
      'n1': nameControllers[1].text,
      'n2': nameControllers[2].text,
      'rounds': rounds.map((r) => r.toJson()).toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1E4D3),
      appBar: AppBar(
        title: Text(gameStarted ? "ID: $_gameId" : "CARROM SETUP"),
        backgroundColor: Colors.brown.shade800,
        foregroundColor: Colors.white,
      ),
      body: gameStarted ? _buildBoard() : _buildSetup(),
    );
  }

  Widget _buildSetup() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("NEUES SPIEL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _modeBtn("2 Spieler", 2),
                    const SizedBox(width: 10),
                    _modeBtn("3 Spieler", 3),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  onPressed: _startNewCloudGame,
                  child: const Text("SPIEL ERSTELLEN"),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("ODER")), Expanded(child: Divider())]),
                ),
                const Text("BEITRETEN", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: _joinController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "ID eingeben (z.B. C-123)",
                    prefixIcon: Icon(Icons.vpn_key),
                  ),
                  onSubmitted: (v) => _connectToGame(v.trim().toUpperCase()),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => _connectToGame(_joinController.text.trim().toUpperCase()),
                  icon: const Icon(Icons.login),
                  label: const Text("MIT ID BEITRETEN"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.brown.shade100),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeBtn(String t, int v) => Expanded(
    child: ChoiceChip(
      label: Text(t),
      selected: mode == v,
      onSelected: (s) => setState(() => mode = v),
    ),
  );

  Widget _buildBoard() {
    return Center(child: Text("Spiel läuft für ID: $_gameId\nRunden: ${rounds.length}")); 
    // Hier kommt dein bestehendes Board-UI rein...
  }
}