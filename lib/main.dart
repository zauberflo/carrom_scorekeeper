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

  factory GameRound.fromJson(Map<String, dynamic> json) => GameRound(
        (json['points'] as Map).map((k, v) => MapEntry(int.parse(k.toString()), v as int)),
        Duration(milliseconds: json['durationMs'] ?? 0),
      );
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
  }

  void _playClick() async {
    try { await _audioPlayer.play(AssetSource('click.mp3')); } catch (_) {}
  }

  // --- CLOUD & SHARE ---
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
          gameStarted = true;
          nameControllers[0].text = data['n0'] ?? "";
          nameControllers[1].text = data['n1'] ?? "";
          nameControllers[2].text = data['n2'] ?? "";
          if (data['rounds'] != null) {
            rounds = (data['rounds'] as List)
                .map((r) => GameRound.fromJson(Map<String, dynamic>.from(r)))
                .toList();
          }
        });
      }
    });
  }

  void _startNewCloudGame() {
    _gameId = "C-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    _updateCloud();
    _connectToGame(_gameId!);
    setState(() {
      gameStarted = true;
      _roundStartTime = DateTime.now();
    });
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
    final String url = "${html.window.location.origin}${html.window.location.pathname}?id=$_gameId";
    Clipboard.setData(ClipboardData(text: url)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Live-Link kopiert! 🔗")));
    });
  }

  // --- HIGHSCORE IMPORT/EXPORT (Repariert) ---
  void _exportFullHistory() {
    String jsonString = jsonEncode(gameHistory);
    Clipboard.setData(ClipboardData(text: jsonString)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Highscore exportiert! 📤")));
    });
  }

  void _importHistoryDialog() {
    TextEditingController importCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Daten importieren"),
        content: TextField(controller: importCtrl, maxLines: 5, decoration: const InputDecoration(hintText: "JSON Code einfügen...")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ABBRECHEN")),
          ElevatedButton(
            onPressed: () async {
              try {
                List<dynamic> imported = jsonDecode(importCtrl.text);
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  for (var entry in imported) {
                    Map<String, dynamic> e = Map<String, dynamic>.from(entry);
                    bool exists = gameHistory.any((old) => old['date'] == e['date'] && old['result'] == e['result']);
                    if (!exists) gameHistory.add(e);
                  }
                  gameHistory.sort((a, b) => b['date'].compareTo(a['date']));
                });
                await prefs.setStringList('history_v5', gameHistory.map((e) => jsonEncode(e)).toList());
                Navigator.pop(ctx);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fehler beim Import!")));
              }
            },
            child: const Text("IMPORT"),
          )
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      List<String> historyStrings = prefs.getStringList('history_v5') ?? [];
      gameHistory = historyStrings.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    });
  }

  // Hilfsmethode für Pucks
  Widget _buildPuck(Color color, {double size = 20, bool hasShadow = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.brown.shade900, width: size / 10),
        boxShadow: hasShadow ? [const BoxShadow(blurRadius: 4, offset: Offset(2, 2))] : null,
      ),
    );
  }

  int getTotalScore(int index) => rounds.fold(0, (sum, r) => sum + (r.teamPoints[index] ?? 0));
  String _formatDuration(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

  // Platzhalter für fehlende Methoden in deinem Snippet (Setup & Board) damit es kompiliert
  Widget _buildSetup() {
    return Center(
      child: ElevatedButton(onPressed: _startNewCloudGame, child: const Text("NEUES SPIEL STARTEN")),
    );
  }

  Widget _buildBoard(int active) {
    return Column(
      children: [
        Text("Spiel läuft (ID: $_gameId)"),
        Expanded(child: ListView(children: [Text("Runden: ${rounds.length}")])),
        ElevatedButton(onPressed: () => _archiveGame("Beendet"), child: const Text("BEENDEN")),
      ],
    );
  }

  Future<void> _archiveGame(String msg) async {
    // Deine Archivierungslogik hier...
    setState(() { gameStarted = false; });
  }

  void _confirmAction(String title, String content, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title), content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("NEIN")),
          TextButton(onPressed: () { onConfirm(); Navigator.pop(ctx); }, child: const Text("JA")),
        ],
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.download, color: Colors.blue), onPressed: _importHistoryDialog),
                const Text("HALL OF FAME", style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.upload, color: Colors.green), onPressed: _exportFullHistory),
              ],
            ),
            const Divider(),
            Expanded(
              child: gameHistory.isEmpty 
                ? const Center(child: Text("Keine Einträge"))
                : ListView.builder(
                    itemCount: gameHistory.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(gameHistory[i]['result'] ?? "Spiel"),
                      subtitle: Text(gameHistory[i]['date'] ?? ""),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("CARROM MASTER"),
        leading: IconButton(icon: const Icon(Icons.emoji_events), onPressed: _showHistory),
      ),
      body: gameStarted ? _buildBoard(mode == 2 ? 2 : 3) : _buildSetup(),
    );
  }
  
  void _saveCurrentGame() async { /* Logik zum Speichern des Zustands */ }
  void _loadStoredNames() async { /* Logik zum Laden der Namen */ }
}