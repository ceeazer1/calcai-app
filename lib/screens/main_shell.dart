import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'wifi_screen.dart';

/// Main navigation shell with a custom glassmorphic bottom navigation bar.
///
/// Uses an [IndexedStack] so each tab's state is preserved when switching.
/// The bottom bar floats above the content with rounded corners and a
/// frosted-glass backdrop.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  /// Tab definitions used to build the bottom bar items.
  static const List<_NavTab> _tabs = [
    _NavTab(icon: Icons.home_rounded, label: 'Home'),
    _NavTab(icon: Icons.history_rounded, label: 'History'),
    _NavTab(icon: Icons.wifi_rounded, label: 'WiFi'),
    _NavTab(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SwitchToWifiTabNotification>(
      onNotification: (notification) {
        setState(() => _currentIndex = 2); // WiFi tab
        return true;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            const DashboardScreen(),
            const HistoryScreen(),
            // Pass tab-active state so the WiFi screen can auto-connect over
            // BLE whenever the user opens this tab.
            WifiScreen(isActive: _currentIndex == 2),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(context),
      ),
    );
  }

  // ── Bottom bar ──────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      // Float the bar above the system navigation area with some breathing
      // room on the sides and bottom.
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomPadding + 12,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.glassBackground,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.glassBorder,
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                _tabs.length,
                (index) => _buildNavItem(index),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final isActive = _currentIndex == index;
    final tab = _tabs[index];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_currentIndex != index) {
          setState(() => _currentIndex = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with animated color transition.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                tab.icon,
                key: ValueKey('${tab.label}_$isActive'),
                size: 24,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            // Label with animated color transition.
            Text(
              tab.label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple data class for a navigation tab.
class _NavTab {
  final IconData icon;
  final String label;

  const _NavTab({required this.icon, required this.label});
}
