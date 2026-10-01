import 'package:flutter/material.dart';
import '../widgets/custom_card.dart';
import '../games/game_screens.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  final List<Map<String, dynamic>> games = const [
    {'title': 'Tic Tac Toe', 'icon': Icons.grid_3x3, 'desc': 'Multiplayer', 'widget': TicTacToeScreen()},
    {'title': 'Flappy Bird', 'icon': Icons.flight, 'desc': 'Retro Flying', 'widget': FlappyBirdScreen()},
    {'title': 'Car Racing', 'icon': Icons.directions_car, 'desc': 'Speed Racing', 'widget': CarRacingScreen()},
    {'title': 'Snake Game', 'icon': Icons.timeline, 'desc': 'Classic Snake', 'widget': SnakeGameScreen()},
    {'title': 'Memory Card', 'icon': Icons.dashboard, 'desc': 'Brain Training', 'widget': MemoryCardScreen()},
    {'title': 'RPS Multi', 'icon': Icons.back_hand, 'desc': 'Rock Paper Scissors', 'widget': RpsMultiScreen()},
    {'title': 'Color Match', 'icon': Icons.color_lens, 'desc': 'Test your vision', 'widget': ColorMatchScreen()},
    {'title': 'Number Puzzle', 'icon': Icons.format_list_numbered, 'desc': 'Logic Challenge', 'widget': NumberPuzzleScreen()},
    {'title': 'Reaction Time', 'icon': Icons.timer, 'desc': 'How fast are you?', 'widget': ReactionTimeScreen()},
    {'title': 'Tap Challenge', 'icon': Icons.touch_app, 'desc': 'Tap Tap Tap!', 'widget': TapChallengeScreen()},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mini Games'),
        centerTitle: true,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: games.length,
        itemBuilder: (context, index) {
          final game = games[index];
          return CustomCard(
            title: game['title'],
            subtitle: game['desc'],
            icon: game['icon'],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => game['widget'] as Widget),
              );
            },
          );
        },
      ),
    );
  }
}
