import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
                  color: AppTheme.primaryColor,
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .boxShadow(
                      begin: BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.5),
                        blurRadius: 30,
                      ),
                      end: BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.8),
                        blurRadius: 40,
                      ),
                    )
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.1, 1.1),
                      duration: 2.seconds,
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
                ).animate().fadeIn(duration: 800.ms).moveY(begin: 20, end: 0),

                const SizedBox(height: 16),

                Text(
                  'Preserve Human Knowledge',
                  style: GoogleFonts.libreBaskerville(
                    fontSize: 18,
                    color: AppTheme.textColor.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ).animate().fadeIn(delay: 500.ms).moveY(begin: 10, end: 0),

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
                      color: AppTheme.primaryColor.withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(
                          alpha: 0.5,
                        ),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(
                            alpha: 0.2,
                          ),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      'ENTER THE ARCHIVE',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                        letterSpacing: 2,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 1000.ms)
                      .shimmer(delay: 1500.ms, duration: 2.seconds),
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
              ).animate().fadeIn(delay: 2000.ms),
            ),
          ),
        ],
      ),
    );
  }
}
