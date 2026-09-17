import 'package:flutter/material.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/ui/onboarding_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasColor,
      body: Stack(
        children: [
          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.auto_stories,
                  size: 80,
                  color: AppTheme.primaryAccent,
                ),

                const SizedBox(height: 32),

                const Text(
                  'ALEXANDRIA',
                  style: TextStyle(
                    fontFamily: 'Newsreader',
                    fontSize: 48,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textColor,
                    letterSpacing: 4,
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  'Preserve Human Knowledge',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    color: AppTheme.textColor.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 64),

                // Entrance Button
                FilledButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OnboardingScreen(),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    foregroundColor: AppTheme.canvasColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                  ),
                  child: const Text(
                    'Enter the archive',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Footer
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Your keys, your node, your copy',
                style: TextStyle(
                  color: AppTheme.textColor.withValues(alpha: 0.3),
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
