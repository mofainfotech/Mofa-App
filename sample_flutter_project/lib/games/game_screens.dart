import 'package:flutter/material.dart';

class GenericGameScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const GenericGameScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 80, color: Colors.orange.shade700),
            ),
            const SizedBox(height: 24),
            Text(
              '🎮 $title 🎮',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Game engine loading...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('EXIT GAME', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}

// Game Screen Classes
class TicTacToeScreen extends GenericGameScreen {
  const TicTacToeScreen({super.key}) : super(title: 'Tic Tac Toe', icon: Icons.grid_3x3);
}

class FlappyBirdScreen extends GenericGameScreen {
  const FlappyBirdScreen({super.key}) : super(title: 'Flappy Bird', icon: Icons.flight);
}

class CarRacingScreen extends GenericGameScreen {
  const CarRacingScreen({super.key}) : super(title: 'Car Racing', icon: Icons.directions_car);
}

class SnakeGameScreen extends GenericGameScreen {
  const SnakeGameScreen({super.key}) : super(title: 'Snake Game', icon: Icons.timeline);
}

class MemoryCardScreen extends GenericGameScreen {
  const MemoryCardScreen({super.key}) : super(title: 'Memory Card', icon: Icons.dashboard);
}

class RpsMultiScreen extends GenericGameScreen {
  const RpsMultiScreen({super.key}) : super(title: 'Rock Paper Scissors', icon: Icons.back_hand);
}

class ColorMatchScreen extends GenericGameScreen {
  const ColorMatchScreen({super.key}) : super(title: 'Color Match', icon: Icons.color_lens);
}

class NumberPuzzleScreen extends GenericGameScreen {
  const NumberPuzzleScreen({super.key}) : super(title: 'Number Puzzle', icon: Icons.format_list_numbered);
}

class ReactionTimeScreen extends GenericGameScreen {
  const ReactionTimeScreen({super.key}) : super(title: 'Reaction Time', icon: Icons.timer);
}

class TapChallengeScreen extends GenericGameScreen {
  const TapChallengeScreen({super.key}) : super(title: 'Tap Challenge', icon: Icons.touch_app);
}
