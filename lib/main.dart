import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/camera_screen.dart';
import 'screens/sign_guide_screen.dart';
import 'screens/upload_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const LatihIsyaratApp());
}

class LatihIsyaratApp extends StatelessWidget {
  const LatihIsyaratApp({super.key, this.cameraEnabled = true});

  final bool cameraEnabled;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0D5C46);
    const surface = Color(0xFFFFFCF4);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: surface,
    );

    return MaterialApp(
      title: 'LatihIsyarat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: surface,
        fontFamily: 'sans-serif-condensed',
        useMaterial3: true,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
            color: Color(0xFF17201D),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE4E9E5)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: HomeShell(cameraEnabled: cameraEnabled),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.cameraEnabled});

  final bool cameraEnabled;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      CameraScreen(cameraEnabled: widget.cameraEnabled && _selectedIndex == 0),
      const UploadScreen(),
      const SignGuideScreen(),
    ];
    final cameraSelected = _selectedIndex == 0;

    return Scaffold(
      extendBody: cameraSelected,
      body: cameraSelected
          ? pages[_selectedIndex]
          : SafeArea(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFCF4), Color(0xFFF2F7F3)],
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: pages[_selectedIndex],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: cameraSelected
              ? NavigationBarThemeData(
                  backgroundColor: const Color(0xE6171F1C),
                  indicatorColor: const Color(0xFF236B55),
                  surfaceTintColor: Colors.transparent,
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    return IconThemeData(
                      color: states.contains(WidgetState.selected)
                          ? Colors.white
                          : const Color(0xFFB9C8C1),
                    );
                  }),
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    return TextStyle(
                      color: states.contains(WidgetState.selected)
                          ? Colors.white
                          : const Color(0xFFB9C8C1),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    );
                  }),
                )
              : const NavigationBarThemeData(),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.videocam_outlined),
              selectedIcon: Icon(Icons.videocam_rounded),
              label: 'Kamera',
            ),
            NavigationDestination(
              icon: Icon(Icons.image_search_outlined),
              selectedIcon: Icon(Icons.image_search_rounded),
              label: 'Upload',
            ),
            NavigationDestination(
              icon: Icon(Icons.sign_language_outlined),
              selectedIcon: Icon(Icons.sign_language_rounded),
              label: 'Rumus ASL',
            ),
          ],
        ),
      ),
    );
  }
}
