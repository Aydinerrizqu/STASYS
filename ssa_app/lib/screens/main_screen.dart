// ============================================
// File: screens/main_screen.dart
// ============================================
import 'package:flutter/material.dart';
import 'tabs/home_tab.dart';
import 'tabs/graph_tab.dart';
import 'tabs/shot_timer_tab.dart';
import 'tabs/connection_tab.dart';
import 'tabs/settings_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  MainScreenState createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    HomeTab(),
    GraphTab(),
    ShotTimerTab(),
    ConnectionTab(),
    SettingsTab(),
  ];

  // List judul untuk ditampilkan di AppBar sesuai tab yang aktif
  final List<String> _titles = [
    'Home',
    'Graph',
    'Shot Timer',
    'Connection',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar diperlukan untuk memunculkan tombol menu (hamburger icon)
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
      ),
      // Menggunakan Drawer untuk menu samping
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Header Drawer (Bagian atas menu biru)
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [
                  Icon(Icons.monitor_heart, color: Colors.white, size: 48),
                  SizedBox(height: 10),
                  Text(
                    'STASYS App',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Menu Item 1: Home
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              selected: _currentIndex == 0,
              onTap: () {
                _onItemTapped(0);
              },
            ),
            // Menu Item 2: Graph
            ListTile(
              leading: const Icon(Icons.analytics),
              title: const Text('Graph'),
              selected: _currentIndex == 1,
              onTap: () {
                _onItemTapped(1);
              },
            ),
            // Menu Item 3: Shot Timer
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('Shot Timer'),
              selected: _currentIndex == 2,
              onTap: () {
                _onItemTapped(2);
              },
            ),
            // Menu Item 4: Connection
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Connection'),
              selected: _currentIndex == 3,
              onTap: () {
                _onItemTapped(3);
              },
            ),
            // Menu Item 5: Settings
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              selected: _currentIndex == 4,
              onTap: () {
                _onItemTapped(4);
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
    );
  }

  // Fungsi untuk menangani perpindahan halaman dan menutup drawer
  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    // Menutup drawer (popup) setelah item dipilih
    Navigator.pop(context);
  }
}