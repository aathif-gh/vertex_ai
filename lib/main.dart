import 'package:flutter/material.dart';
import 'screens/meeting_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Otter.ai-inspired palette: deep indigo/blue primary, clean white canvas
    const seedColor = Color(0xFF2563EB); // Otter.ai's signature blue

    return MaterialApp(
      title: 'Meeting Transcription',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
          primary: seedColor,
          secondary: const Color(0xFF7C3AED),   // Violet accent (like Otter's tags)
          surface: const Color(0xFFF8FAFC),     // Soft white surface
          onSurface: const Color(0xFF1E293B),   // Deep slate text
          surfaceContainerHighest: const Color(0xFFE2E8F0),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E40AF),   // Deep blue header
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF2563EB),
          foregroundColor: Colors.white,
          elevation: 4,
          shape: StadiumBorder(),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Color(0xFFBFDBFE),
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
        ),
        useMaterial3: true,
      ),
      home: const MeetingScreen(),
    );
  }
}
