import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'screens/contacts_screen.dart';
import 'screens/my_key_screen.dart';
import 'screens/options_screen.dart';
import 'screens/open_screen.dart';
import 'screens/send_screen.dart';
import 'services/ncry_keys.dart';
import 'services/theme_preferences.dart';
import 'theme/ncrypted_theme.dart';
import 'widgets/brand_lockup.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupPath = await _resolveInitialNcryPath(args);
  runApp(NcryptedApp(initialNcryPath: startupPath));
}

class NcryptedApp extends StatefulWidget {
  const NcryptedApp({super.key, this.initialNcryPath});

  final String? initialNcryPath;

  @override
  State<NcryptedApp> createState() => _NcryptedAppState();
}

class _NcryptedAppState extends State<NcryptedApp> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _easterEggEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _loadSecurityVisualMode();
  }

  Future<void> _loadThemeMode() async {
    final savedMode = await ThemePreferences.loadThemeMode();
    if (!mounted) return;
    setState(() => _themeMode = savedMode);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await ThemePreferences.saveThemeMode(mode);
  }

  Future<void> _loadSecurityVisualMode() async {
    final isMax = await KeyStore.isActiveIdentityMaxProfile();
    if (!mounted) return;
    setState(() => _easterEggEnabled = isMax);
  }

  void _setEasterEggEnabled(bool value) {
    if (!mounted) return;
    setState(() => _easterEggEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ncrypted',
      debugShowCheckedModeBanner: false,
      theme: NcryptedTheme.light(useSabrePalette: _easterEggEnabled),
      darkTheme: NcryptedTheme.dark(useSabrePalette: _easterEggEnabled),
      themeMode: _themeMode,
      home: HomeShell(
        initialNcryPath: widget.initialNcryPath,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        easterEggEnabled: _easterEggEnabled,
        onEasterEggChanged: _setEasterEggEnabled,
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.initialNcryPath,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.easterEggEnabled,
    required this.onEasterEggChanged,
  });

  final String? initialNcryPath;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool easterEggEnabled;
  final ValueChanged<bool> onEasterEggChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialNcryPath == null ? 0 : 3;
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      MyKeyScreen(
        easterEggEnabled: widget.easterEggEnabled,
        onEasterEggChanged: widget.onEasterEggChanged,
      ),
      const ContactsScreen(),
      SendScreen(onEasterEggChanged: widget.onEasterEggChanged),
      OpenScreen(initialNcryPath: widget.initialNcryPath),
      OptionsScreen(
        currentThemeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onEasterEggChanged: widget.onEasterEggChanged,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 84,
        titleSpacing: 16,
        title: BrandLockup(
          logoSize: 42,
          wordmarkSize: 20,
          wordmarkLetterSpacing: 1.4,
          taglineToWordmarkRatio: 0.42,
          taglineLetterSpacingRatio: 0.01,
          easterEggEnabled: widget.easterEggEnabled,
        ),
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code),
            label: 'My Key',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.send_outlined),
            label: 'Send',
          ),
          NavigationDestination(
            icon: Icon(Icons.lock_open_outlined),
            label: 'Open',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Options',
          ),
        ],
      ),
    );
  }
}

Future<String?> _resolveInitialNcryPath(List<String> args) async {
  final fromArgs = _extractNcryPath(args);
  if (fromArgs != null) return fromArgs;
  final fromPlatform = await _extractFromPlatformChannel();
  return fromPlatform;
}

String? _extractNcryPath(List<String> args) {
  final isWindowsHost = defaultTargetPlatform == TargetPlatform.windows;
  for (final raw in args) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;

    String candidate = trimmed;
    if (candidate.startsWith('file://')) {
      final uri = Uri.tryParse(candidate);
      if (uri != null && uri.scheme == 'file') {
        candidate = uri.toFilePath(windows: isWindowsHost);
      } else {
        candidate = Uri.decodeFull(candidate.replaceFirst('file://', ''));
      }
    } else {
      candidate = Uri.decodeComponent(candidate);
    }

    if (candidate.toLowerCase().endsWith('.ncry')) {
      return candidate;
    }
  }
  return null;
}

Future<String?> _extractFromPlatformChannel() async {
  const channel = MethodChannel('ncrypted/launch');
  try {
    final path = await channel.invokeMethod<String>('getInitialNcryPath');
    if (path == null || path.trim().isEmpty) return null;
    return path;
  } catch (_) {
    return null;
  }
}
