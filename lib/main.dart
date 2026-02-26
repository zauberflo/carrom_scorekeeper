import 'package:flutter/material.dart';

void main() => runApp(const CarromApp());

class CarromApp extends StatelessWidget {
  const CarromApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.brown, useMaterial3: true),
      home: const CarromScorePage(),
    );
  }
}

class Player {
  String name;
  Color color;
  Player({required this.name, required this.color});
}

class GameRound {
  final Map<int, int> playerPoints; 
  GameRound(this.playerPoints);
}

class CarromScorePage extends StatefulWidget {
  const CarromScorePage({super.key});
  @override
  State<CarromScorePage> createState() => _CarromScorePageState();
}

class _CarromScorePageState extends State<CarromScorePage> {
  // Einstellungen
  int playerCount = 2;
  int targetScore = 20;
  bool gameStarted = false;

  List<Player> players = [
    Player(name: "Spieler Weiß", color: Colors.white),
    Player(name: "Spieler Schwarz", color: Colors.black),
    Player(name: "Spieler 3", color: Colors.red),
    Player(name: "Spieler 4", color: Colors.blue),
  ];

  List<GameRound> rounds = [];
  
  // Controller für die direkte Punkteingabe pro Runde
  List<TextEditingController> pointControllers = List.generate(4, (_) => TextEditingController());

  int getTotalScore(int index) {
    return rounds.fold(0, (sum, round) => sum + (round.playerPoints[index] ?? 0));
  }

  void submitRound() {
    Map<int, int> roundData = {};
    for (int i = 0; i < playerCount; i++) {
      int pts = int.tryParse(pointControllers[i].text) ?? 0;
      roundData[i] = pts;
      pointControllers[i].clear();
    }
    setState(() {
      rounds.add(GameRound(roundData));
    });
    
    // Check for Winner
    for (int i = 0; i < playerCount; i++) {
      if (getTotalScore(i) >= targetScore) {
        _showWinnerDialog(players[i].name);
        break;
      }
    }
  }

  void _showWinnerDialog(String winner) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Spielende!"),
        content: Text("$winner hat gewonnen!"),
        actions: [TextButton(onPressed: () {
          setState(() => rounds.clear());
          Navigator.pop(ctx);
        }, child: const Text("Neues Spiel"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5E6CA),
      appBar: AppBar(
        title: const Text("Carrom Scoreboard"),
        backgroundColor: Colors.brown.shade300,
        actions: [
          if (gameStarted) IconButton(icon: const Icon(Icons.settings), onPressed: () => setState(() => gameStarted = false)),
        ],
      ),
      body: !gameStarted ? _buildSetupScreen() : _buildGameScreen(),
    );
  }

  // --- SETUP SCREEN ---
  Widget _buildSetupScreen() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Spiel-Setup", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            value: playerCount,
            decoration: const InputDecoration(labelText: "Anzahl Spieler"),
            items: [2, 3, 4].map((n) => DropdownMenuItem(value: n, child: Text("$n Spieler"))).toList(),
            onChanged: (val) => setState(() => playerCount = val!),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: targetScore.toString(),
            decoration: const InputDecoration(labelText: "Punkteziel (z.B. 20)"),
            keyboardType: TextInputType.number,
            onChanged: (val) => targetScore = int.tryParse(val) ?? 20,
          ),
          const SizedBox(height: 20),
          const Text("Namen editieren:"),
          ...List.generate(playerCount, (i) => TextFormField(
            initialValue: players[i].name,
            decoration: InputDecoration(icon: Icon(Icons.person, color: players[i].color)),
            onChanged: (val) => players[i].name = val,
          )),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () => setState(() => gameStarted = true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(200, 50)),
            child: const Text("Spiel starten"),
          )
        ],
      ),
    );
  }

  // --- GAME SCREEN ---
  Widget _buildGameScreen() {
    return Column(
      children: [
        // Das Board mit den aktiven Spielern
        Container(
          height: 180,
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFD2B48C), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.brown, width: 5)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(playerCount, (i) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(backgroundColor: players[i].color, radius: 20, child: i == 0 ? const Icon(Icons.circle, color: Colors.black26) : null),
                Text(players[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text("${getTotalScore(i)}", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              ],
            )),
          ),
        ),
        // Eingabe der aktuellen Runde
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              ...List.generate(playerCount, (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: TextField(
                    controller: pointControllers[i],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: "Pkt ${players[i].name.split(' ')[0]}", border: const OutlineInputBorder()),
                  ),
                ),
              )),
              IconButton(
                icon: const Icon(Icons.add_box, size: 40, color: Colors.brown),
                onPressed: submitRound,
              )
            ],
          ),
        ),
        const Divider(),
        const Text("Rundenverlauf", style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: ListView.builder(
            itemCount: rounds.length,
            itemBuilder: (context, index) {
              final r = rounds[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: ListTile(
                  dense: true,
                  title: Text("Runde ${index + 1}"),
                  subtitle: Text(List.generate(playerCount, (i) => "${players[i].name}: ${r.playerPoints[i]}").join(" | ")),
                  trailing: IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () => setState(() => rounds.removeAt(index))),
                ),
              );
            },
          ),
        )
      ],
    );
  }
}