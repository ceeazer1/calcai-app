import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'notes_screen.dart';
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
    _NavTab(icon: Icons.edit_note_rounded, label: 'Notes'),
    _NavTab(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    // Wi-Fi management now lives as a full page opened from Home rather than a
    // bottom-nav tab. Any [SwitchToWifiTabNotification] still opens it, pushed
    // on top of the shell.
    return NotificationListener<SwitchToWifiTabNotification>(
      onNotification: (notification) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WifiScreen()),
        );
        return true;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex,
          children: const [
            DashboardScreen(),
            HistoryScreen(),
            NotesScreen(),
            SettingsScreen(),
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
            // Expanded, not spaceAround: the items have fixed padding, so on
            // a narrow phone (320pt) four of them are wider than the bar and
            // the Row overflows. Sharing the width lets them compress.
            child: Row(
              children: List.generate(
                _tabs.length,
                (index) => Expanded(child: _buildNavItem(index)),
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
