import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'dart:html' as html;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("Firebase Fehler: $e");
  }
  runApp(const CarromApp());
}

class CarromApp extends StatelessWidget {
  const CarromApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown)),
      home: const CarromScorePage(),
    );
  }
}

class GameRound {
  final Map<int, int> teamPoints;
  GameRound(this.teamPoints);
  Map<String, dynamic> toJson() => {'points': teamPoints.map((k, v) => MapEntry(k.toString(), v))};
  factory GameRound.fromJson(Map<String, dynamic> json) {
    var pts = json['points'] as Map;
    return GameRound(pts.map((k, v) => MapEntry(int.parse(k.toString()), v as int)));
  }
}

class CarromScorePage extends StatefulWidget {
  const CarromScorePage({super.key});
  @override
  State<CarromScorePage> createState() => _CarromScorePageState();
}

class _CarromScorePageState extends State<CarromScorePage> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  String? _gameId;
  int mode = 2;
  bool gameStarted = false;
  bool _isSyncing = false; 
  String _connectionStatus = "Bereit"; // Verbindungsnachweis
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
    setState(() {
      _isSyncing = true;
      _connectionStatus = "Verbinde zu $id...";
    });

    _db.child('games/$id').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() {
          _gameId = id;
          mode = data['mode'] ?? 2;
          nameControllers[0].text = data['n0'] ?? "";
          nameControllers[1].text = data['n1'] ?? "";
          nameControllers[2].text = data['n2'] ?? "";
          if (data['rounds'] != null) {
            rounds = (data['rounds'] as List).map((r) => GameRound.fromJson(Map<String, dynamic>.from(r))).toList();
          }
          gameStarted = true;
          _isSyncing = false;
          _connectionStatus = "Verbunden";
        });
      } else {
        setState(() {
          _isSyncing = false;
          _connectionStatus = "ID $id nicht gefunden!";
        });
      }
    }, onError: (error) {
      setState(() {
        _isSyncing = false;
        _connectionStatus = "Fehler: $error";
      });
    });
  }

  void _startNewGame() {
    _gameId = "C-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    rounds = [];
    _updateCloud();
    _connectToGame(_gameId!);
  }

  void _updateCloud() {
    // SCHREIB-STOPP: Verhindert das Löschen der Daten beim ersten Sync
    if (_gameId == null || _isSyncing) return; 
    _db.child('games/$_gameId').set({
      'mode': mode,
      'n0': nameControllers[0].text,
      'n1': nameControllers[1].text,
      'n2': nameControllers[2].text,
      'rounds': rounds.map((r) => r.toJson()).toList(),
    });
  }

  void _addRound() {
    Map<int, int> data = {};
    for (int i = 0; i < mode; i++) {
      data[i] = int.tryParse(scoreControllers[i].text) ?? 0;
      scoreControllers[i].clear();
    }
    setState(() => rounds.add(GameRound(data)));
    _updateCloud();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(gameStarted ? "ID: $_gameId" : "CARROM SETUP"),
        backgroundColor: Colors.brown.shade800,
        foregroundColor: Colors.white,
      ),
      body: gameStarted ? _buildBoard() : _buildSetup(),
    );
  }

  Widget _buildSetup() {
    return Container(
      color: const Color(0xFFF1E4D3),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("NEUES SPIEL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                ElevatedButton(onPressed: _startNewGame, child: const Text("SPIEL ERSTELLEN")),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("ODER")), Expanded(child: Divider())]),
                ),
                const Text("SPIEL BEITRETEN", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: _joinController,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(hintText: "ID eingeben", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => _connectToGame(_joinController.text.trim().toUpperCase()),
                  child: const Text("JETZT BEITRETEN"),
                ),
                const SizedBox(height: 15),
                // --- VERBINDUNGSNACHWEIS ---
                Text("Status: $_connectionStatus", style: TextStyle(color: _isSyncing ? Colors.orange : Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(mode, (i) => Column(children: [
            Text("${rounds.fold(0, (sum, r) => sum + (r.teamPoints[i] ?? 0))}", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            Text(nameControllers[i].text.isEmpty ? "P${i+1}" : nameControllers[i].text),
          ])),
        ),
        const Divider(height: 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              ...List.generate(mode, (i) => Expanded(child: TextField(controller: scoreControllers[i], keyboardType: TextInputType.number, textAlign: TextAlign.center))),
              IconButton.filled(onPressed: _addRound, icon: const Icon(Icons.add)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rounds.length,
            itemBuilder: (context, i) => ListTile(title: Text("Runde ${i + 1}: ${rounds[i].teamPoints.values.join(' | ')}")),
          ),
        ),
        TextButton(onPressed: () {
          final String url = "${html.window.location.origin}${html.window.location.pathname}?id=$_gameId";
          Clipboard.setData(ClipboardData(text: url));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link kopiert!")));
        }, child: const Text("Einladungs-Link kopieren")),
      ],
    );
  }
}