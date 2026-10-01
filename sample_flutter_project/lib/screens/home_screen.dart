import 'package:flutter/material.dart';
import '../widgets/custom_card.dart';
import '../tools/tool_screens.dart';
import '../games/game_screens.dart';
import 'apps_screen.dart';
import 'downloads_screen.dart';
import 'games_screen.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mofa Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'View Downloads',
            icon: const Icon(Icons.download_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],

      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreeting(context, theme),
              const SizedBox(height: 32),
              _buildSectionHeader(context, 'Featured Apps', Icons.apps, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AppsScreen()));
              }),
              const SizedBox(height: 16),
              _buildAppsList(context),
              const SizedBox(height: 32),
              _buildSectionHeader(context, 'Popular Games', Icons.sports_esports, () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GamesScreen()));
              }),
              const SizedBox(height: 16),
              _buildGamesList(context),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back,',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Explore the Best Tools & Games',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, VoidCallback onViewMore) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        TextButton(
          onPressed: onViewMore,
          child: const Text('View More'),
        ),
      ],
    );
  }

  Widget _buildAppsList(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildHorizontalCard(context, 'YT Downloader', 'Video & Audio', Icons.ondemand_video, const YTDownloaderScreen()),
          _buildHorizontalCard(context, 'QR Generator', 'Create QR codes', Icons.qr_code_2, const QRGeneratorScreen()),
          _buildHorizontalCard(context, 'Text to Speech', 'Read text aloud', Icons.record_voice_over, const TtsScreen()),
          _buildHorizontalCard(context, 'Speech to Text', 'Convert audio to text', Icons.mic, const SttScreen()),
        ],
      ),
    );
  }

  Widget _buildGamesList(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildHorizontalCard(context, 'Tic Tac Toe', 'Multiplayer Classic', Icons.grid_3x3, const TicTacToeScreen()),
          _buildHorizontalCard(context, 'Flappy Bird', 'Endless Flying', Icons.flight, const FlappyBirdScreen()),
          _buildHorizontalCard(context, 'Car Racing', 'Speed & Drift', Icons.directions_car, const CarRacingScreen()),
          _buildHorizontalCard(context, 'Snake', 'Retro Survival', Icons.timeline, const SnakeGameScreen()),
        ],
      ),
    );
  }

  Widget _buildHorizontalCard(BuildContext context, String title, String subtitle, IconData icon, Widget targetScreen) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 16),
      child: CustomCard(
        title: title,
        subtitle: subtitle,
        icon: icon,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => targetScreen),
          );
        },
      ),
    );
  }
}
