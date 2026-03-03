import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    debugPrint("Firebase Init Error: $e");
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown, surface: const Color(0xFFF1E4D3)),
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
  bool gameStarted = false;
  List<GameRound> rounds = [];
  DateTime _roundStartTime = DateTime.now();

  final List<TextEditingController> scoreControllers = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> nameControllers = List.generate(3, (i) => TextEditingController());
  final TextEditingController _joinController = TextEditingController();
  late TextEditingController targetScoreController;

  @override
  void initState() {
    super.initState();
    targetScoreController = TextEditingController(text: targetScore.toString());
    _checkUrlForGame();
  }

  void _playClick() async {
    try { await _audioPlayer.play(AssetSource('click.mp3')); } catch (_) {}
  }

  // --- CLOUD & JOIN LOGIK ---
  void _checkUrlForGame() {
    final Uri uri = Uri.parse(html.window.location.href);
    String? id = uri.queryParameters['id'];
    if (id == null && html.window.location.hash.contains('id=')) {
      id = Uri.parse(html.window.location.hash.replaceFirst('#/', '')).queryParameters['id'];
    }
    if (id != null && id.isNotEmpty) _connectToGame(id.toUpperCase());
  }

  void _connectToGame(String id) {
    _db.child('games/$id').onValue.listen((event) {
      final data = event.snapshot.value;
      if (data != null) {
        final map = Map<String, dynamic>.from(data as Map);
        setState(() {
          _gameId = id;
          mode = map['mode'] ?? 2;
          targetScore = map['target'] ?? 25;
          nameControllers[0].text = map['n0'] ?? "";
          nameControllers[1].text = map['n1'] ?? "";
          nameControllers[2].text = map['n2'] ?? "";
          
          if (map['rounds'] != null) {
            rounds = (map['rounds'] as List)
                .map((r) => GameRound.fromJson(Map<String, dynamic>.from(r)))
                .toList();
          } else {
            rounds = [];
          }
          gameStarted = true; // Springt sofort ins Spiel
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Spiel-ID nicht gefunden!")));
      }
    });
  }

  void _startNewCloudGame() {
    String newId = "C-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    _gameId = newId;
    _updateCloud(); 
    _connectToGame(newId);
    _playClick();
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

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.brown.shade800,
        foregroundColor: Colors.white,
        title: Text(gameStarted ? "ID: $_gameId" : "CARROM CLOUD"),
        actions: [
          if (gameStarted) IconButton(icon: const Icon(Icons.share), onPressed: _shareGame)
        ],
      ),
      body: !gameStarted ? _buildSetup() : _buildBoard(),
    );
  }

  Widget _buildSetup() {
    return Center(
      child: SingleChildScrollView(
        child: Card(
          margin: const EdgeInsets.all(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text("NEUES SPIEL", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(children: [
                  _modeBtn("2 SPIELER", 2), const SizedBox(width: 10), _modeBtn("3 SPIELER", 3)
                ]),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _startNewCloudGame, child: const Text("SPIEL ERSTELLEN")),
                const Divider(height: 40),
                const Text("BEITRETEN", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: _joinController,
                  decoration: const InputDecoration(hintText: "ID eingeben (z.B. C-123)"),
                  textAlign: TextAlign.center,
                ),
                TextButton(onPressed: () => _connectToGame(_joinController.text.trim().toUpperCase()), child: const Text("JETZT BEITRETEN"))
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeBtn(String txt, int val) => Expanded(
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: mode == val ? Colors.brown : Colors.grey.shade300),
      onPressed: () => setState(() => mode = val),
      child: Text(txt, style: TextStyle(color: mode == val ? Colors.white : Colors.black)),
    ),
  );

  Widget _buildBoard() {
    return Column(
      children: [
        // Score-Anzeige
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(mode, (i) => Column(children: [
              Text("${_getTotal(i)}", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              Text(nameControllers[i].text.isEmpty ? "P${i+1}" : nameControllers[i].text),
            ])),
          ),
        ),
        // Eingabe
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              ...List.generate(mode, (i) => Expanded(child: TextField(controller: scoreControllers[i], keyboardType: TextInputType.number, textAlign: TextAlign.center))),
              IconButton.filled(onPressed: _submitRound, icon: const Icon(Icons.add)),
            ],
          ),
        ),
        // Liste
        Expanded(
          child: ListView.builder(
            itemCount: rounds.length,
            itemBuilder: (context, i) {
              final r = rounds[rounds.length - 1 - i];
              return ListTile(title: Text("Runde ${rounds.length - i}: ${r.teamPoints.values.join(' : ')}"));
            },
          ),
        )
      ],
    );
  }

  int _getTotal(int idx) => rounds.fold(0, (sum, r) => sum + (r.teamPoints[idx] ?? 0));

  void _submitRound() {
    Map<int, int> data = {};
    for (int i = 0; i < mode; i++) {
      data[i] = int.tryParse(scoreControllers[i].text) ?? 0;
      scoreControllers[i].clear();
    }
    setState(() {
      rounds.add(GameRound(data, DateTime.now().difference(_roundStartTime)));
      _roundStartTime = DateTime.now();
    });
    _updateCloud();
    _playClick();
  }

  void _shareGame() {
    final String url = "${html.window.location.origin}${html.window.location.pathname}?id=$_gameId";
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link kopiert!")));
  }
}