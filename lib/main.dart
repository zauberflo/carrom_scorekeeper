import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown, primary: Colors.brown[900]),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const CarromScorePage(),
    );
  }
}

class GameRound {
  final String key;
  final Map<int, int> teamPoints;
  final String duration;
  GameRound({required this.key, required this.teamPoints, required this.duration});

  factory GameRound.fromSnapshot(String key, dynamic value) {
    final Map<int, int> extractedPoints = {};
    String extractedDuration = "0:00";
    if (value is Map) {
      extractedDuration = value['duration']?.toString() ?? "0:00";
      final pointsData = value['points'];
      if (pointsData != null) {
        if (pointsData is Map) {
          pointsData.forEach((k, v) {
            final int? teamIdx = int.tryParse(k.toString());
            final int? score = int.tryParse(v.toString());
            if (teamIdx != null && score != null) extractedPoints[teamIdx] = score;
          });
        } else if (pointsData is List) {
          for (int i = 0; i < pointsData.length; i++) {
            if (pointsData[i] != null) {
              extractedPoints[i] = int.tryParse(pointsData[i].toString()) ?? 0;
            }
          }
        }
      }
    }
    return GameRound(key: key, teamPoints: extractedPoints, duration: extractedDuration);
  }
}

class CarromScorePage extends StatefulWidget {
  const CarromScorePage({super.key});
  @override
  State<CarromScorePage> createState() => _CarromScorePageState();
}

class _CarromScorePageState extends State<CarromScorePage> {
  final String myDbURL = "https://carrom-scorekeeper-default-rtdb.europe-west1.firebasedatabase.app/";
  late DatabaseReference _db;
  final TextEditingController _joinCtrl = TextEditingController();
  final TextEditingController _targetCtrl = TextEditingController();
  final List<TextEditingController> scoreCtrls = List.generate(3, (_) => TextEditingController());
  final List<TextEditingController> nameCtrls = List.generate(5, (_) => TextEditingController());
  String? _gameId;
  int mode = 2; 
  bool gameStarted = false;
  bool isPaused = false; 
  bool isTvMode = false;
  bool _canUndo = false; 
  List<GameRound> rounds = [];
  bool isConnecting = false;
  int _roundStartTs = 0;
  int _alreadyElapsedSeconds = 0;
  bool _victoryAlreadyHandled = false;

  @override
  void initState() {
    super.initState();
    _db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: myDbURL).ref();
    _targetCtrl.text = "25";
    _loadSavedData();
  }

  String _formatDuration(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return "$hours Std. $minutes Min.";
    }
    return "$minutes Min.";
  }

  void _exportToCsv(List<MapEntry> dataList) {
    String csv = "Datum;Sieger;Punkte;Details;Modus\n";
    for (var entry in dataList) {
      var v = entry.value;
      csv += "${v['date']};${v['winner']};${v['score']};${v['details']};${v['game_mode']}\n";
    }
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("CSV-Daten in Zwischenablage kopiert!")));
  }

  void _showInfo() {
    final String apiUrl = "https://carrom-scorekeeper-default-rtdb.europe-west1.firebasedatabase.app/live_api.json";
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.brown[900],
        title: const Text("App Info 🍺", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Version: 3.2.4", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text("App von Senior Codemaster Flo", style: TextStyle(color: Colors.white, fontSize: 12, fontStyle: FontStyle.italic)),
            const SizedBox(height: 15),
            const Text("„Zwischen Leber und Milz passt immer noch ein Pils – und eine Runde Carrom!“", style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 15),
            const Text("JSON API Endpunkt:", style: TextStyle(color: Colors.white, fontSize: 12)),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: apiUrl));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("API-Link in Zwischenablage kopiert!")));
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(5)),
                child: const Text("Klick hier zum Kopieren des API-Links", style: TextStyle(color: Colors.blueAccent, fontSize: 12, decoration: TextDecoration.underline)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Prost!", style: TextStyle(color: Colors.amber)))
        ],
      ),
    );
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (int i = 0; i < 4; i++) {
        nameCtrls[i].text = prefs.getString('n$i') ?? "Spieler ${i + 1}";
      }
      mode = prefs.getInt('mode') ?? 2;
      _targetCtrl.text = prefs.getString('target') ?? "25";
      String? lastId = prefs.getString('last_game_id');
      if (lastId != null) {
        _connectToGame(lastId.replaceFirst("C-", ""));
      }
    });
  }

  Future<void> _saveCurrentNames() async {
    final prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < 4; i++) {
      await prefs.setString('n$i', nameCtrls[i].text);
    }
    await prefs.setInt('mode', mode);
    await prefs.setString('target', _targetCtrl.text);
  }

  Future<void> _saveActiveGame(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_game_id', id);
  }

  Future<void> _clearActiveGame() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_game_id');
  }

  void _updateLiveApi() {
    if (_gameId == null) return;
    _db.child('live_api').set({
      'game_id': _gameId,
      'mode': mode,
      'target': _targetCtrl.text,
      'is_paused': isPaused,
      'names': mode == 2 ? ["${nameCtrls[0].text}/${nameCtrls[1].text}", "${nameCtrls[2].text}/${nameCtrls[3].text}"] : [nameCtrls[0].text, nameCtrls[1].text, nameCtrls[2].text],
      'scores': List.generate(mode == 2 ? 2 : 3, (i) => _getTotal(i)),
      'rounds_played': rounds.length,
      'last_update': ServerValue.timestamp,
    });
  }

  void _listenToGame(String id) {
    _db.child('games/$id/config').onValue.listen((event) {
      final data = event.snapshot.value;
      if (data is Map && mounted) {
        setState(() {
          _gameId = id;
          mode = int.tryParse(data['mode'].toString()) ?? 2;
          _targetCtrl.text = data['target']?.toString() ?? (mode == 2 ? "25" : "66");
          for (int i = 0; i < 4; i++) {
            nameCtrls[i].text = data['n$i']?.toString() ?? "Spieler ${i+1}";
          }
          isPaused = data['is_paused'] == true;
          _roundStartTs = data['round_start_ts'] ?? DateTime.now().millisecondsSinceEpoch;
          _alreadyElapsedSeconds = data['elapsed_seconds'] ?? 0;
          gameStarted = true;
          isConnecting = false;
        });
        _saveActiveGame(id);
        _updateLiveApi();
      }
    });
    _db.child('games/$id/rounds').onValue.listen((event) {
      final data = event.snapshot.value;
      if (mounted) {
        final List<GameRound> tempRounds = [];
        if (data is Map) {
          data.forEach((key, value) => tempRounds.add(GameRound.fromSnapshot(key.toString(), value)));
          tempRounds.sort((a, b) => a.key.compareTo(b.key));
        }
        setState(() => rounds = tempRounds);
        _updateLiveApi();
        _checkWinner(currentRounds: tempRounds);
      }
    });
  }

  void _startNewGame() {
    _saveCurrentNames();
    _victoryAlreadyHandled = false;
    HapticFeedback.vibrate();
    String newId = "C-${(1000 + math.Random().nextInt(8999))}";
    setState(() => _canUndo = false);
    _db.child('games/$newId/config').set({
      'mode': mode, 
      'target': int.tryParse(_targetCtrl.text) ?? 25,
      'n0': nameCtrls[0].text, 'n1': nameCtrls[1].text, 
      'n2': nameCtrls[2].text, 'n3': nameCtrls[3].text,
      'is_paused': false,
      'round_start_ts': ServerValue.timestamp,
      'elapsed_seconds': 0,
    });
    _listenToGame(newId);
  }

  void _connectToGame(String id) async {
    String cleanId = id.trim().toUpperCase();
    if (cleanId.isEmpty) return;
    setState(() {
      isConnecting = true;
      _victoryAlreadyHandled = false;
    });
    final snap = await _db.child('games/C-$cleanId/config').get();
    if (snap.exists) {
      _listenToGame("C-$cleanId");
    } else {
      setState(() => isConnecting = false);
      _showError("ID C-$cleanId nicht gefunden");
    }
  }

  void _submitRound() {
    HapticFeedback.mediumImpact();
    if (_gameId == null || isPaused || _victoryAlreadyHandled) return;
    int v0 = int.tryParse(scoreCtrls[0].text) ?? 0;
    int v1 = int.tryParse(scoreCtrls[1].text) ?? 0;
    int v2 = mode == 3 ? (int.tryParse(scoreCtrls[2].text) ?? 0) : 0;
    
    if (mode == 3 && (v0 + v1 + v2 != 12 && v0 + v1 + v2 != 17)) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Hinweis: Summe ist nicht 12 oder 17!"), backgroundColor: Colors.orange));
    }
    
    int target = int.tryParse(_targetCtrl.text) ?? 25;
    List<int> currentTotals = List.generate(mode == 2 ? 2 : 3, (i) => _getTotal(i));
    currentTotals[0] += v0;
    currentTotals[1] += v1;
    if (mode == 3) currentTotals[2] += v2;

    int? immediateWinner;
    for(int i=0; i<currentTotals.length; i++) {
       if(currentTotals[i] >= target) { immediateWinner = i; break; }
    }
    if (immediateWinner == null && mode == 2 && rounds.length + 1 >= 8) {
       immediateWinner = currentTotals[0] >= currentTotals[1] ? 0 : 1;
    }

    if (immediateWinner != null) {
      String winnerName = "";
      if (mode == 2) {
        winnerName = immediateWinner == 0 ? "${nameCtrls[0].text} & ${nameCtrls[1].text}" : "${nameCtrls[2].text} & ${nameCtrls[3].text}";
      } else {
        winnerName = nameCtrls[immediateWinner].text;
      }
      _saveHighscore(winnerName, immediateWinner, customTotals: currentTotals);
      _db.child('live_api').update({'winner': winnerName});
    }
    
    final nowTs = DateTime.now().millisecondsSinceEpoch;
    final sessionSeconds = ((nowTs - _roundStartTs) / 1000).floor();
    final totalSeconds = _alreadyElapsedSeconds + sessionSeconds;
    final timeStr = "${(totalSeconds / 60).floor()}:${(totalSeconds % 60).toString().padLeft(2, '0')}";
    
    Map<String, int> pointsMap = {"0": v0, "1": v1};
    if (mode == 3) pointsMap["2"] = v2;
    _db.child('games/$_gameId/rounds').push().set({'points': pointsMap, 'duration': timeStr});
    _db.child('games/$_gameId/config').update({'round_start_ts': ServerValue.timestamp, 'elapsed_seconds': 0});
    for (var c in scoreCtrls) { c.clear(); }
    setState(() { _canUndo = true; });
  }

  void _togglePause() async {
    if (_gameId == null) return;
    if (!isPaused) {
      final nowTs = DateTime.now().millisecondsSinceEpoch;
      final sessionSeconds = ((nowTs - _roundStartTs) / 1000).floor();
      final newTotalElapsed = _alreadyElapsedSeconds + sessionSeconds;
      await _db.child('games/$_gameId/config').update({'is_paused': true, 'elapsed_seconds': newTotalElapsed});
    } else {
      await _db.child('games/$_gameId/config').update({'is_paused': false, 'round_start_ts': ServerValue.timestamp});
    }
  }

  void _checkWinner({List<GameRound>? currentRounds}) {
    if (_victoryAlreadyHandled) return;
    final activeRounds = currentRounds ?? rounds;
    int target = int.tryParse(_targetCtrl.text) ?? 25;
    int activeIdx = (mode == 2 ? 2 : 3);
    List<int> totals = List.generate(activeIdx, (idx) {
      return activeRounds.fold(0, (sum, r) => sum + (r.teamPoints[idx] ?? 0));
    });
    int? detectedWinner;
    for (int i = 0; i < activeIdx; i++) {
      if (totals[i] >= target) { detectedWinner = i; break; }
    }
    if (detectedWinner == null && mode == 2 && activeRounds.length >= 8) {
      detectedWinner = totals[0] >= totals[1] ? 0 : 1;
    }
    if (detectedWinner != null) {
      _handleVictoryScenario(detectedWinner);
    }
  }

  void _handleVictoryScenario(int winnerIdx) {
    setState(() => _victoryAlreadyHandled = true);
    String winnerName = "";
    if (mode == 2) {
      winnerName = winnerIdx == 0 ? "${nameCtrls[0].text} & ${nameCtrls[1].text}" : "${nameCtrls[2].text} & ${nameCtrls[3].text}";
    } else {
      winnerName = nameCtrls[winnerIdx].text;
    }
    _showVictoryDialog(winnerName);
  }

  void _saveHighscore(String winner, int idx, {List<int>? customTotals}) {
    DateTime now = DateTime.now();
    List<String> actualNames = [];
    int finalScore = customTotals != null ? customTotals[idx] : _getTotal(idx);
    
    int totalDurationInSeconds = rounds.fold(0, (sum, r) {
      List<String> parts = r.duration.split(':');
      return sum + (int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!);
    });

    if (mode == 2) {
      int start = (idx == 0) ? 0 : 2;
      for (int i = start; i < start + 2; i++) {
        String n = nameCtrls[i].text.trim();
        if (n.isNotEmpty && !n.startsWith("Spieler ")) actualNames.add(n);
      }
    } else {
      String n = nameCtrls[idx].text.trim();
      if (n.isNotEmpty && !n.startsWith("Spieler ")) actualNames.add(n);
    }
    if (actualNames.isEmpty) return;

    String modePrefix = mode == 2 ? "[TEAM]" : "[EINZEL]";
    List<MapEntry<String, int>> leaderboard = [];
    if (mode == 2) {
      leaderboard.add(MapEntry("${nameCtrls[0].text}/${nameCtrls[1].text}", customTotals != null ? customTotals[0] : _getTotal(0)));
      leaderboard.add(MapEntry("${nameCtrls[2].text}/${nameCtrls[3].text}", customTotals != null ? customTotals[1] : _getTotal(1)));
    } else {
      for (int i = 0; i < 3; i++) {
        leaderboard.add(MapEntry(nameCtrls[i].text, customTotals != null ? customTotals[i] : _getTotal(i)));
      }
    }
    leaderboard.sort((a, b) => b.value.compareTo(a.value));
    String details = "$modePrefix ";
    List<String> medals = ["🥇", "🥈", "🥉"];
    List<String> entries = [];
    for (int i = 0; i < leaderboard.length; i++) {
      entries.add("${medals[i]} ${leaderboard[i].key} (${leaderboard[i].value})");
    }
    details += entries.join(" | ");

    _db.child('highscores').push().set({
      'winner': actualNames.join(" & "), 
      'score': finalScore, 
      'date': DateFormat('dd.MM.yy HH:mm').format(now),
      'details': details,
      'game_mode': mode,
      'timestamp': ServerValue.timestamp, 
      'year': now.year, 
      'month': now.month,
      'duration_seconds': totalDurationInSeconds,
    });
  }

  int _getTotal(int teamIdx) => rounds.fold(0, (sum, r) => sum + (r.teamPoints[teamIdx] ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5AB), 
      appBar: AppBar(
        title: Text(gameStarted ? "ID: $_gameId" : "CARROM MASTER", style: gameStarted ? null : GoogleFonts.astloch(fontSize: 24, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.brown[900], foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showInfo),
          if (gameStarted) IconButton(icon: const Icon(Icons.tv), onPressed: () => setState(() => isTvMode = true)),
          if (gameStarted) IconButton(icon: Icon(isPaused ? Icons.play_arrow : Icons.smoking_rooms), onPressed: _togglePause),
          if (gameStarted) IconButton(icon: const Icon(Icons.undo), onPressed: _canUndo ? _confirmUndo : null),
          if (gameStarted) IconButton(icon: const Icon(Icons.exit_to_app), onPressed: _confirmExit),
          if (!gameStarted) IconButton(icon: const Icon(Icons.leaderboard), onPressed: _showStats),
        ],
      ),
      body: !gameStarted ? _buildSetup() : _buildBoard(mode == 2 ? 2 : 3),
    );
  }

  Widget _buildSetup() {
    return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(children: [
      Container(padding: const EdgeInsets.all(20), decoration: _boxStyle(), child: Column(children: [
        ToggleButtons(
          isSelected: [mode == 2, mode == 3],
          selectedColor: Colors.white, fillColor: Colors.brown[900], borderRadius: BorderRadius.circular(10),
          onPressed: (i) => setState(() { mode = i == 0 ? 2 : 3; _targetCtrl.text = mode == 3 ? "66" : "25"; }),
          children: const [Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text("Team")), Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text("Einzel"))],
        ),
        const SizedBox(height: 20),
        TextField(controller: _targetCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Zielpunkte", border: OutlineInputBorder())),
        if (mode == 2) ...[
          const Padding(padding: EdgeInsets.only(top: 15), child: Text("Team Weiß", style: TextStyle(fontWeight: FontWeight.bold))),
          TextField(controller: nameCtrls[0], decoration: const InputDecoration(hintText: "Spieler 1")),
          TextField(controller: nameCtrls[1], decoration: const InputDecoration(hintText: "Spieler 2")),
          const Padding(padding: EdgeInsets.only(top: 15), child: Text("Team Schwarz", style: TextStyle(fontWeight: FontWeight.bold))),
          TextField(controller: nameCtrls[2], decoration: const InputDecoration(hintText: "Spieler 1")),
          TextField(controller: nameCtrls[3], decoration: const InputDecoration(hintText: "Spieler 2")),
        ] else ...[
          ...List.generate(3, (i) => Padding(padding: const EdgeInsets.only(top: 10), child: TextField(controller: nameCtrls[i], decoration: InputDecoration(labelText: "Spieler ${i+1}", border: const OutlineInputBorder())))),
        ],
      ])),
      const SizedBox(height: 25),
      ElevatedButton(onPressed: _startNewGame, style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60), backgroundColor: Colors.brown[900], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text("SPIEL STARTEN", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
      const Divider(height: 40),
      TextField(controller: _joinCtrl, decoration: InputDecoration(hintText: "ID (z.B. 4567)", prefixText: "C-", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)))),
      const SizedBox(height: 10),
      isConnecting ? const CircularProgressIndicator() : ElevatedButton(onPressed: () => _connectToGame(_joinCtrl.text), child: const Text("BEITRETEN")),
    ])));
  }

  Widget _buildBoard(int active) {
    if (isTvMode) {
      return _buildTvView(active);
    }
    List<int> totals = List.generate(active, (i) => _getTotal(i));
    int target = int.tryParse(_targetCtrl.text) ?? 25;
    int maxS = totals.reduce(math.max);
    int minS = totals.reduce(math.min);

    return Column(children: [
      if (mode == 2) Container(width: double.infinity, color: Colors.brown[100], child: Padding(padding: const EdgeInsets.all(4), child: Text("Runde ${rounds.length} / 8", textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)))),
      if (isPaused) Container(width: double.infinity, color: Colors.orange, child: const Text("🚬 PAUSE - ZEIT GESTOPPT", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
      Padding(padding: const EdgeInsets.all(15), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: List.generate(active, (i) {
        bool isL = totals[i] == maxS && maxS > 0;
        bool isLast = totals[i] == minS && maxS > 0 && active > 1;
        String displayName = mode == 2 ? (i == 0 ? "${nameCtrls[0].text}\n${nameCtrls[1].text}" : "${nameCtrls[2].text}\n${nameCtrls[3].text}") : nameCtrls[i].text;
        double progress = (totals[i] / target).clamp(0.0, 1.0);
        double beerLevel = 1.0 - progress;
        return Stack(clipBehavior: Clip.none, children: [
            Container(width: 110, height: 160, decoration: BoxDecoration(color: const Color(0xFFF9F1D0), border: Border.all(color: Colors.black, width: 2.5), borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(2, 2))]),
              child: Stack(alignment: Alignment.center, children: [
                  Opacity(opacity: 0.1, child: Icon(Icons.adjust, size: 80, color: Colors.brown[900])),
                  Positioned(bottom: 0, child: ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)), child: AnimatedContainer(duration: const Duration(seconds: 1), width: 110, height: 110 * beerLevel, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.amber[300]!, Colors.amber[600]!, Colors.amber[700]!]))))),
                  Padding(padding: const EdgeInsets.all(8.0), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 15),
                    Text("${totals[i]}", style: GoogleFonts.monoton(fontSize: 34, color: i == 0 ? Colors.brown[900] : Colors.black)),
                    const SizedBox(height: 5),
                    Text(displayName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black87), overflow: TextOverflow.visible),
                  ])),
                ])),
            if (isL || isLast) Positioned(top: -22, left: 0, right: 0, child: Center(child: Text(isL ? "👑" : "💩", style: const TextStyle(fontSize: 38)))),
        ]);
      }))),
      Container(margin: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: Colors.brown[900], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black, width: 2)), padding: const EdgeInsets.all(12), child: Row(children: [
        ...List.generate(active, (i) => Expanded(child: TextField(controller: scoreCtrls[i], keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white, fontSize: 22), textAlign: TextAlign.center, decoration: const InputDecoration(hintText: "0", hintStyle: TextStyle(color: Colors.white30), border: InputBorder.none)))),
        IconButton(icon: const Icon(Icons.add_circle, color: Colors.white, size: 45), onPressed: _submitRound),
      ])),
      Expanded(child: ListView.builder(itemCount: rounds.length, itemBuilder: (c, i) {
        final r = rounds[rounds.length - 1 - i];
        return Card(elevation: 1, color: Colors.white.withOpacity(0.85), margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Colors.black54, width: 0.5)),
          child: ListTile(dense: true, leading: const Icon(Icons.history, size: 20, color: Colors.brown),
            title: Text(List.generate(active, (idx) {
              String n = mode == 2 ? (idx == 0 ? "Team Weiß" : "Team Schwarz") : nameCtrls[idx].text;
              return "$n: ${r.teamPoints[idx] ?? 0}";
            }).join(" | "), style: const TextStyle(fontWeight: FontWeight.bold)), 
            subtitle: Text("Runde ${rounds.length - i} • ${r.duration}")
          )
        );
      })),
    ]);
  }

int? _tempSelectedMonth; 

void _showStats() {
  _tempSelectedMonth = null; // Reset beim Öffnen

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => StatefulBuilder(
      builder: (context, setModalState) {
        return StreamBuilder(
          stream: _db.child('highscores').onValue,
          builder: (context, snapshot) {
            final data = snapshot.hasData ? (snapshot.data!.snapshot.value as Map? ?? {}) : {};
            
            // 1. Alle Monate sammeln, in denen tatsächlich Spiele stattfanden
            List<int> availableMonths = [];
            data.forEach((k, v) {
              if (v['month'] != null) availableMonths.add(v['month'] as int);
            });
            availableMonths = availableMonths.toSet().toList()..sort((a, b) => b.compareTo(a)); // Neueste zuerst

            // 2. Intelligente Vorauswahl: 
            // Wenn noch nichts gewählt ist, nimm den Monat des allerletzten Spiels (statt stur HEUTE)
            if (_tempSelectedMonth == null) {
              if (availableMonths.contains(DateTime.now().month)) {
                _tempSelectedMonth = DateTime.now().month;
              } else if (availableMonths.isNotEmpty) {
                _tempSelectedMonth = availableMonths.first; // Der letzte Monat mit Daten
              } else {
                _tempSelectedMonth = DateTime.now().month;
              }
            }

            return DefaultTabController(
              length: 3,
              child: SizedBox(
                height: 650,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text("STATISTIK 🏆"),
                    actions: [IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), onPressed: () => _confirmResetStats(c))],
                    bottom: const TabBar(tabs: [Tab(text: "Ranking"), Tab(text: "Monat"), Tab(text: "Jahre")]),
                  ),
                  body: TabBarView(children: [
                    _buildPlayerRanking(data),
                    Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: DropdownButton<int>(
                          value: availableMonths.contains(_tempSelectedMonth) ? _tempSelectedMonth : (availableMonths.isNotEmpty ? availableMonths.first : _tempSelectedMonth),
                          items: availableMonths.map((m) => DropdownMenuItem(value: m, child: Text("Monat $m"))).toList(),
                          onChanged: (v) => setModalState(() => _tempSelectedMonth = v!),
                        ),
                      ),
                      // year: null entfernt, damit der Monat angezeigt wird, egal aus welchem Jahr
                      Expanded(child: _buildStatsList(data, month: _tempSelectedMonth)),
                    ]),
                    _buildYearlyTimeTab(data),
                  ]),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

Widget _buildYearlyTimeTab(Map data) {
  // Gruppiere nach Jahr und berechne Zeit pro Jahr
  Map<int, List<MapEntry>> yearlyData = {};
  Map<int, int> yearlySeconds = {};

  data.forEach((k, v) {
    int y = v['year'] ?? DateTime.now().year;
    int d = v['duration_seconds'] ?? 0;
    
    yearlyData.putIfAbsent(y, () => []).add(MapEntry(k, v));
    yearlySeconds[y] = (yearlySeconds[y] ?? 0) + d;
  });

  return ListView(
    children: yearlyData.entries.map((e) {
      int totalMinutes = (yearlySeconds[e.key] ?? 0) ~/ 60;
      return ExpansionTile(
        title: Text("Jahr ${e.key}"),
        subtitle: Text("Gesamtzeit: ${_formatDuration(yearlySeconds[e.key] ?? 0)} | ${e.value.length} Spiele"),
        children: [
          ...e.value.map((m) => ListTile(
            title: Text("${m.value['winner']} (${m.value['score']} Pkt)"),
            subtitle: Text(m.value['date']),
            dense: true,
          )),
          ListTile(
            leading: const Icon(Icons.download, color: Colors.green),
            title: const Text("Export als CSV"),
            onTap: () => _exportToCsv(e.value),
          )
        ],
      );
    }).toList(),
  );
}
Widget _buildPlayerRanking(Map data) {
  Map<String, int> winCount = {};
  Map<String, DateTime> lastWinDate = {};
  Set<String> allParticipants = {}; 
  DateTime now = DateTime.now();

  final List<String> blackList = [
    '[team]', '[einzel]', 'weiß', 'weiss', 'schwarz', 
    'gegen', 'vs', 'punkte', 'sieger', 'spieler', 'runde', 'spiel'
  ];

  data.forEach((k, v) {
    String rawWinner = v['winner']?.toString() ?? "";
    String rawDetails = v['details']?.toString() ?? "";
    DateTime matchDate = v['timestamp'] != null 
        ? DateTime.fromMillisecondsSinceEpoch(v['timestamp']) 
        : DateTime.now();

    // 1. Namen aus Details extrahieren
    List<String> detailParts = rawDetails
        .split(RegExp(r'(&|vs\.?|und|,|/|\(|\)|\s+)', caseSensitive: false))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.length > 2 && !blackList.contains(e.toLowerCase()))
        .toList();
    for (var p in detailParts) { allParticipants.add(p); }

    // 2. Gewinner zählen
    List<String> winners = rawWinner.contains("&") 
        ? rawWinner.split("&").map((e) => e.trim()).toList() 
        : [rawWinner];

    for (var w in winners) {
      String cleanW = w.trim();
      if (cleanW.isNotEmpty && !blackList.contains(cleanW.toLowerCase()) && cleanW != "Ehem. Legende" && cleanW != "Unbekannt") {
        allParticipants.add(cleanW);
        winCount[cleanW] = (winCount[cleanW] ?? 0) + 1;
        if (lastWinDate[cleanW] == null || matchDate.isAfter(lastWinDate[cleanW]!)) {
          lastWinDate[cleanW] = matchDate;
        }
      }
    }
  });

  // Globalen letzten Sieg finden
  DateTime? absoluteLastWinTime;
  if (lastWinDate.isNotEmpty) {
    absoluteLastWinTime = lastWinDate.values.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  var rankingList = allParticipants.map((name) {
    return {
      'name': name,
      'wins': winCount[name] ?? 0,
      'lastWin': lastWinDate[name],
    };
  }).toList();

  // VERBESSERTE SORTIERUNG:
  rankingList.sort((a, b) {
    // 1. Nach Siegen sortieren
    int winCmp = (b['wins'] as int).compareTo(a['wins'] as int);
    if (winCmp != 0) return winCmp;

    // 2. Bei Gleichstand: Wer hat zuletzt gewonnen?
    DateTime? dateA = a['lastWin'] as DateTime?;
    DateTime? dateB = b['lastWin'] as DateTime?;
    if (dateA != null && dateB != null) {
      return dateB.compareTo(dateA); // Neueres Datum zuerst
    } else if (dateA != null) return -1;
      else if (dateB != null) return 1;

    // 3. Alphabetisch
    return (a['name'] as String).compareTo(b['name'] as String);
  });

  if (rankingList.isEmpty) return const Center(child: Text("Noch keine Spiele in der Datenbank."));

  return ListView.builder(
    itemCount: rankingList.length,
    itemBuilder: (c, i) {
      final player = rankingList[i];
      String name = player['name'] as String;
      int wins = player['wins'] as int;
      DateTime? lastWin = player['lastWin'] as DateTime?;
      
      bool isCurrentChamp = lastWin != null && lastWin == absoluteLastWinTime;

      String subtitle;
      if (wins == 0) {
        subtitle = "Wartet noch auf den ersten Sieg... 🍗";
      } else if (isCurrentChamp) {
        subtitle = "AKTUELLER GEWINNER 🏆";
      } else {
        int days = now.difference(lastWin!).inDays;
        subtitle = "Seit $days Tagen sieglos 💀";
      }

      return ListTile(
        leading: CircleAvatar(
          backgroundColor: isCurrentChamp ? Colors.amber : (wins > 0 ? Colors.brown[900] : Colors.grey[400]),
          child: Text("${i + 1}", style: TextStyle(color: isCurrentChamp ? Colors.black : Colors.white, fontSize: 12)),
        ),
        title: Text(name, style: TextStyle(
          fontWeight: wins > 0 ? FontWeight.bold : FontWeight.normal,
          color: isCurrentChamp ? Colors.orange[900] : Colors.black,
        )),
        subtitle: Text(subtitle, style: TextStyle(
          fontSize: 11, 
          fontWeight: isCurrentChamp ? FontWeight.bold : FontWeight.normal,
          color: isCurrentChamp ? Colors.orange[800] : Colors.grey[600],
        )),
        trailing: Text("$wins Siege", 
          style: TextStyle(
            fontWeight: wins > 0 ? FontWeight.bold : FontWeight.normal,
            color: wins > 0 ? Colors.brown[900] : Colors.grey
          )
        ),
      );
    },
  );
}

  Widget _buildStatsList(Map data, {int? month, int? year}) {
    var list = data.entries.where((e) {
      if (year != null && e.value['year'] != year) return false;
      if (month != null && e.value['month'] != month) return false;
      return true;
    }).toList()..sort((a, b) => (b.value['timestamp'] ?? 0).compareTo(a.value['timestamp'] ?? 0));
    return ListView.builder(itemCount: list.length, itemBuilder: (c, i) {
      final val = list[i].value;
      int gMode = val['game_mode'] ?? 2;
      return Card(margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: ListTile(
        leading: Icon(gMode == 2 ? Icons.group : Icons.person, color: Colors.brown),
        title: Text("${val['winner']} (${val['score']} Pkt)"), 
        subtitle: Text("${val['details']}\n📅 ${val['date']} | Spielzeit: ${_formatDuration(val['duration_seconds'] ?? 0)}"),
        trailing: IconButton(icon: const Icon(Icons.share, size: 20), onPressed: () => _shareMatch(val)),
      ));
    });
  }

  void _shareMatch(Map match) {
    String text = "🏆 CARROM GEWONNEN!\n\n👑 Sieger: ${match['winner']}\n📊 Punkte: ${match['score']}\n📝 Info: ${match['details']}\n📅 Datum: ${match['date']}\n\nAus der Carrom Master App! 🍻";
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Match-Info in Zwischenablage kopiert!")));
  }
  void _confirmResetStats(BuildContext ctx) {
    final TextEditingController deleteValCtrl = TextEditingController();
    final TextEditingController securityCtrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Daten verwalten"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Name oder Monat (1-12) zum Löschen:", style: TextStyle(fontSize: 12)),
        TextField(controller: deleteValCtrl, decoration: const InputDecoration(hintText: "z.B. 'Florian' oder 'Monat 3'")),
        const SizedBox(height: 10),
        const Text("Zur Sicherheit 'LOESCHEN' eingeben:"),
        TextField(controller: securityCtrl, decoration: const InputDecoration(hintText: "LOESCHEN")),
      ]),
      actions: [
        TextButton(onPressed: () { 
          if (securityCtrl.text == "LOESCHEN") { 
            int? m = int.tryParse(deleteValCtrl.text);
            if (m != null && m >= 1 && m <= 12) { _performReset('month', extra: m.toString()); } else { _performReset('player', extra: deleteValCtrl.text); }
            Navigator.pop(c); 
          }
        }, child: const Text("Gezielt entfernen", style: TextStyle(color: Colors.orange))),
        TextButton(onPressed: () { if (securityCtrl.text == "LOESCHEN") { _performReset('all'); Navigator.pop(c); } }, child: const Text("Alles löschen", style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Abbrechen")),
      ],
    ));
  }

  void _performReset(String type, {String? extra}) async {
  final snap = await _db.child('highscores').get();
  if (!snap.exists) return;
  Map data = snap.value as Map;
  
  data.forEach((key, val) {
    if (type == 'all') {
      _db.child('highscores/$key').remove();
    } else if (type == 'month' && extra != null && val['month'].toString() == extra) {
      _db.child('highscores/$key').remove();
    } else if (type == 'player' && extra != null && extra.isNotEmpty) {
      String winnerRaw = val['winner']?.toString() ?? "";
      String detailsRaw = val['details']?.toString() ?? "";
      
      // Wir erstellen eine Regex mit Wortgrenzen \b
      // RegExp.escape sorgt dafür, dass Sonderzeichen im Namen die Regex nicht zerschießen
      final String escapedName = RegExp.escape(extra);
      final RegExp nameRegex = RegExp('\\b$escapedName\\b', caseSensitive: false);

      // Prüfen, ob der EXAKTE Name vorkommt
      if (nameRegex.hasMatch(winnerRaw) || nameRegex.hasMatch(detailsRaw)) {
        
        // Nur den exakten Namen durch "Ehem. Legende" ersetzen
        String newWinner = winnerRaw.replaceAll(nameRegex, "Ehem. Legende");
        String newDetails = detailsRaw.replaceAll(nameRegex, "Ehem. Legende");
        
        _db.child('highscores/$key').update({
          'winner': newWinner,
          'details': newDetails
        });
      }
    }
  });
}
  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));

  void _confirmUndo() { if (rounds.isNotEmpty && _canUndo) { showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Runde löschen?"), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Nein")), TextButton(onPressed: () { _db.child('games/$_gameId/rounds/${rounds.last.key}').remove(); setState(() => _canUndo = false); Navigator.pop(c); }, child: const Text("Ja"))])); } }
  
  void _confirmExit() { showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Spiel verlassen?"), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Nein")), TextButton(onPressed: () { _clearActiveGame(); Navigator.pop(c); setState(() => gameStarted = false); }, child: const Text("Ja, Beenden"))])); }
  
  void _showVictoryDialog(String winner) => showDialog(context: context, barrierDismissible: false, builder: (c) => AlertDialog(title: Text("🏆 $winner HAT GEWONNEN!"), content: const Text("Statistik wurde aktualisiert."), actions: [TextButton(onPressed: () { _clearActiveGame(); Navigator.pop(c); setState(() { gameStarted = false; _victoryAlreadyHandled = false; }); }, child: const Text("ZURÜCK"))]));
  
  BoxDecoration _boxStyle() => BoxDecoration(color: const Color(0xFFF9F1D0), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black, width: 2));

  Widget _buildTvView(int active) {
    int totalSec = rounds.fold(0, (sum, r) {
      List<String> parts = r.duration.split(':');
      return sum + (int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!);
    });
    String timeStr = "${(totalSec / 60).floor()}:${(totalSec % 60).toString().padLeft(2, '0')}";

    return GestureDetector(
      onTap: () => setState(() => isTvMode = false),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("CARROM LIVE", style: GoogleFonts.monoton(color: Colors.amber, fontSize: 50)),
              Text("Runde: ${rounds.length} | Zeit: $timeStr", style: const TextStyle(color: Colors.white54, fontSize: 20)),
              const SizedBox(height: 50),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(active, (i) {
                  String displayNames = "";
                  if (mode == 2) {
                    displayNames = (i == 0) 
                        ? "${nameCtrls[0].text} & ${nameCtrls[1].text}" 
                        : "${nameCtrls[2].text} & ${nameCtrls[3].text}";
                  } else {
                    displayNames = nameCtrls[i].text;
                  }

                  return Column(children: [
                    Text(displayNames, 
                         textAlign: TextAlign.center, 
                         style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("${_getTotal(i)}", style: GoogleFonts.monoton(color: Colors.amber, fontSize: 120)),
                  ]);
                }),
              ),
              const SizedBox(height: 50),
              const Text("Tippen zum Beenden", style: TextStyle(color: Colors.white12, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}