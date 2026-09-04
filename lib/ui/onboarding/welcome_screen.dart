import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/ui/onboarding_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background - Deep Space / Starfield
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0F172A), Color(0xFF334155)],
              ),
            ),
          ),

          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.temple_buddhist,
                  size: 80,
                  color: AppTheme.primaryAccent,
                ),

                const SizedBox(height: 32),

                Text(
                  'ALEXANDRIA',
                  style: GoogleFonts.cinzel(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor,
                    letterSpacing: 4,
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  'Preserve Human Knowledge',
                  style: GoogleFonts.libreBaskerville(
                    fontSize: 18,
                    color: AppTheme.textColor.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 64),

                // Entrance Button
                GestureDetector(
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OnboardingScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: AppTheme.primaryAccent.withValues(
                          alpha: 0.5,
                        ),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryAccent.withValues(
                            alpha: 0.2,
                          ),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      'Enter the archive',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryAccent,
                        letterSpacing: 0,
                      ),
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
                'Decentralized • Encrypted • Eternal',
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
