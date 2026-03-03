import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
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
    debugPrint("Firebase Init: $e");
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

class Team {
  String name;
  Color color;
  Team({required this.name, required this.color});
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
  bool gameStarted = false;
  List<GameRound> rounds = [];
  List<Map<String, dynamic>> gameHistory = [];
  DateTime _roundStartTime = DateTime.now();

  List<Team> teams = [
    Team(name: "Weiß", color: Colors.white),
    Team(name: "Schwarz", color: const Color(0xFF2C2C2C)),
    Team(name: "Rot", color: const Color(0xFFB71C1C)),
  ];

  final List<TextEditingController> scoreControllers = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> nameControllers = List.generate(3, (i) => TextEditingController());
  late TextEditingController targetScoreController;

  @override
  void initState() {
    super.initState();
    targetScoreController = TextEditingController(text: targetScore.toString());
    _loadData();
    _checkUrlForGame();
    for (var c in scoreControllers) { c.addListener(() => setState(() {})); }
  }

  void _playClick() async {
    try { await _audioPlayer.play(AssetSource('click.mp3')); } catch (_) {}
  }

  // --- CLOUD LOGIK (KORRIGIERT) ---
  void _checkUrlForGame() {
    final uri = Uri.base;
    if (uri.queryParameters.containsKey('id')) {
      _gameId = uri.queryParameters['id'];
      _connectToGame(_gameId!);
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
          gameStarted = true; // Erst wenn Daten da sind, Screen umschalten
        });
      }
    });
  }

  void _startNewCloudGame() {
    _gameId = "C-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    setState(() {
      gameStarted = true;
      rounds = [];
      _roundStartTime = DateTime.now();
    });
    _updateCloud(); // Erstellt den Eintrag in Firebase
    _connectToGame(_gameId!); // Startet den Listener für Sync
    _saveCurrentGame();
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

  void _shareGame() {
    _playClick();
    final String url = "${html.window.location.origin}${html.window.location.pathname}?id=$_gameId";
    Clipboard.setData(ClipboardData(text: url)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link kopiert! 🔗")));
    });
  }

  // --- SCORE LOGIK ---
  void submitRound() {
    _playClick();
    Map<int, int> data = {};
    int total = 0;
    int active = (mode == 2 ? 2 : 3);

    for (int i = 0; i < active; i++) {
      int p = int.tryParse(scoreControllers[i].text) ?? 0;
      data[i] = p;
      total += p;
    }

    if (total > 0) {
      setState(() {
        rounds.add(GameRound(data, DateTime.now().difference(_roundStartTime)));
        _roundStartTime = DateTime.now();
      });
      for (var c in scoreControllers) { c.clear(); }
      _updateCloud();
      _saveCurrentGame();
      _checkGameStatus();
    }
  }

  int getTotalScore(int idx) => rounds.fold(0, (sum, r) => sum + (r.teamPoints[idx] ?? 0));

  void _checkGameStatus() {
    for (int i = 0; i < (mode == 2 ? 2 : 3); i++) {
      if (getTotalScore(i) >= targetScore) {
        _showWinnerDialog("${nameControllers[i].text} GEWINNT!", i);
        return;
      }
    }
  }

  // --- UI KOMPONENTEN ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1E4D3),
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.brown.shade800,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.emoji_events), onPressed: _showHistory),
        title: InkWell(
          onTap: gameStarted ? _shareGame : null,
          child: Text(gameStarted ? "ID: $_gameId" : "CARROM MASTER"),
        ),
      ),
      body: !gameStarted ? _buildSetup() : _buildBoard(),
    );
  }

  Widget _buildSetup() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("NEUES SPIEL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(children: [
                _modeBtn("TEAM", 2), const SizedBox(width: 10), _modeBtn("SOLO", 3)
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: targetScoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Zielpunkte"),
                onChanged: (v) => targetScore = int.tryParse(v) ?? 25,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _startNewCloudGame,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text("STARTEN"),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeBtn(String label, int val) {
    bool sel = mode == val;
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: sel ? Colors.brown : Colors.grey),
        onPressed: () => setState(() { mode = val; targetScore = val == 3 ? 66 : 25; targetScoreController.text = targetScore.toString(); }),
        child: Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildBoard() {
    int active = mode == 2 ? 2 : 3;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(active, (i) => Column(children: [
              _buildPuck(teams[i].color, size: 40),
              Text("${getTotalScore(i)}", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              Text(nameControllers[i].text.isEmpty ? "Spieler ${i+1}" : nameControllers[i].text),
            ])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ...List.generate(active, (i) => Expanded(
                child: TextField(controller: scoreControllers[i], keyboardType: TextInputType.number, textAlign: TextAlign.center),
              )),
              IconButton.filled(onPressed: submitRound, icon: const Icon(Icons.add)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rounds.length,
            itemBuilder: (context, i) {
              final r = rounds[rounds.length - 1 - i];
              return Card(child: ListTile(title: Text("Runde ${rounds.length - i}: ${r.teamPoints.values.join(' | ')}")));
            },
          ),
        )
      ],
    );
  }

  Widget _buildPuck(Color c, {double size = 20}) => Container(width: size, height: size, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(width: 2)));

  // --- STUBS FÜR IMPORT/EXPORT & HISTORY (Wie in deinem Snippet) ---
  void _showHistory() { /* Deine ModalBottomSheet Logik */ }
  void _exportFullHistory() { /* Deine Export Logik */ }
  void _importHistoryDialog() { /* Deine Import Logik */ }
  void _archiveGame(String m, {int? winnerIdx}) { /* Deine Archiv Logik */ }
  void _loadData() async { /* Deine SharedPreferences Logik */ }
  void _saveCurrentGame() async { /* Deine SharedPreferences Logik */ }
  void _showWinnerDialog(String m, int i) { /* Deine Dialog Logik */ }
}