import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ui/alexandria_root.dart';

export 'ui/alexandria_root.dart' show AlexandriaApp, AlexandriaRoot;

void main() {
  // (round-6 red finding) Never fetch fonts at runtime: google_fonts'
  // first-render download from fonts.gstatic.com uses a direct
  // connection - bypassing Tor and leaking the real IP - and fails
  // offline. Every family the UI references is bundled under
  // assets/fonts/, so disabling runtime fetching loses nothing; any
  // missing font now fails visibly instead of leaking.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const AlexandriaRoot());
}
