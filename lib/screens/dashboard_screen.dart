import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';
import 'link_device_screen.dart';
import 'wifi_screen.dart';
import '../utils/latex_readable.dart';
import '../utils/safe_image.dart';

/// Model IDs usable on the free plan. Everything else is premium.
const Set<String> kFreeModels = {
  'gpt-5-mini',
  'gemini-3.5-flash',
  'gemini-3.1-flash-lite',
  'claude-haiku-4-5',
};

bool isFreeModel(String model) => kFreeModels.contains(model);

/// Notification dispatched when the user taps "Connect Device" on the
/// locked dashboard. MainShell listens for this to switch to the WiFi tab.
class SwitchToWifiTabNotification extends Notification {}

/// Main dashboard screen — the hub after login.
///
/// Shows device status, AI model selector, usage info, and quick actions.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<double> _fadeIn;
  bool _isLoadingModel = false;

  /// Collapsed (skinny bar) vs expanded (original two-column card) usage view.

  /// Whether the response-style inline dropdown is open.
  bool _styleExpanded = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOut,
    );
    _enterController.forward();

    // Load dashboard data
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    if (auth.token != null && auth.primaryMac != null) {
      await cloud.loadDashboard(auth.token!, auth.primaryMac!);
    }
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: RefreshIndicator(
            onRefresh: _loadData,
            color: AppColors.electricBlue,
            backgroundColor: AppColors.surface,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              children: [
                _buildTopBar(),
                _buildPairBanner(),
                _buildSectionHeader('Today', Icons.calendar_today_rounded),
                const SizedBox(height: 12),
                _buildUsage(),
                const SizedBox(height: 16),
                _buildSectionHeader('AI', Icons.auto_awesome_rounded),
                const SizedBox(height: 12),
                _buildModelSelector(),
                const SizedBox(height: 10),
                _buildStyleDropdown(),
                const SizedBox(height: 24),
                _buildSectionHeader('Recent', Icons.history_rounded),
                const SizedBox(height: 12),
                _buildLastPromptCard(),
                const SizedBox(height: 24),
                _buildSectionHeader('Wi-Fi', Icons.wifi_rounded),
                const SizedBox(height: 12),
                _buildWifiCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Minimal top spacer. The old "CalcAI" logo + calculator icon were removed;
  /// this reserves a little breathing room for a future centered element.
  Widget _buildTopBar() {
    return const SizedBox(height: 8);
  }

  /// Slim "pair your device" prompt, shown only when no device is linked
  /// (e.g. the user chose "Set up later"). Tapping launches the setup flow.
  Widget _buildPairBanner() {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        if (auth.primaryMac != null && auth.primaryMac!.isNotEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LinkDeviceScreen()),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_link_rounded,
                    color: AppColors.electricBlue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pair your CalcAI to get started',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Section heading with a small leading icon (calendar / sparkles / history /
  /// wifi) sitting before the title.
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.electricBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Returns the display provider name (e.g. "OpenAI") if the current model's
  /// provider has a saved API key — i.e. the user's own key is in use.
  String? _byokProvider(CloudService cloud) {
    final model = cloud.currentModel ?? '';
    String? key, label;
    if (model.startsWith('claude')) {
      key = 'anthropic';
      label = 'Anthropic';
    } else if (model.startsWith('gemini')) {
      key = 'google';
      label = 'Google';
    } else if (model.startsWith('gpt') || model.startsWith('o')) {
      key = 'openai';
      label = 'OpenAI';
    }
    if (key != null && cloud.hasApiKey(key)) return label;
    return null;
  }

  Widget _buildModelSelector() {
    return Consumer<CloudService>(
      builder: (context, cloud, _) {
        return GlassCard(
          padding: const EdgeInsets.all(16),
          onTap: () => _showModelPicker(cloud),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Model',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cloud.currentModel ?? 'Not set',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_byokProvider(cloud) != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.vpn_key_rounded,
                              size: 11, color: AppColors.electricBlue),
                          const SizedBox(width: 4),
                          Text(
                            'Using your ${_byokProvider(cloud)} key',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.electricBlue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_isLoadingModel)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.textSecondary),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Response-style presets, shared by the dropdown row and its picker sheet.
  static const List<(String, String, String, IconData)> _styles = [
    ('answer', 'Answers only', 'Just the final answers', Icons.bolt_rounded),
    ('small', 'Brief explanation', 'Answers with short work', Icons.notes_rounded),
    ('detailed', 'Detailed explanation', 'Full step-by-step work',
        Icons.menu_book_rounded),
  ];

  /// "Response style" inline dropdown: a compact row that, on tap, animates
  /// open to reveal the presets right below it (chevron rotates, list expands).
  Widget _buildStyleDropdown() {
    return Consumer<CloudService>(
      builder: (context, cloud, _) {
        final current = cloud.responseStyle;
        final match = _styles.firstWhere(
          (s) => s.$1 == current,
          orElse: () => _styles[1],
        );
        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header row (tap to toggle) ────────────────
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      setState(() => _styleExpanded = !_styleExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    child: Row(
                      children: [
                        Icon(match.$4,
                            size: 20, color: AppColors.textSecondary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Response style',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                match.$2,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: _styleExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Animated options list ─────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _styleExpanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 0.5,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 14),
                            color: AppColors.glassBorder,
                          ),
                          ..._styles.map((s) => _styleOption(s, current)),
                          const SizedBox(height: 6),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A single option row inside the response-style dropdown.
  Widget _styleOption(
      (String, String, String, IconData) s, String current) {
    final isSelected = s.$1 == current;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _setStyle(s.$1);
          setState(() => _styleExpanded = false);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(
                s.$4,
                size: 20,
                color: isSelected
                    ? AppColors.electricBlue
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.$2,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      s.$3,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.electricBlue,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the full Wi-Fi management page, which connects to the CalcAI over
  /// Bluetooth and walks the user through adding a network.
  void _openWifi() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WifiScreen()),
    );
  }

  /// Home-screen Wi-Fi section: the saved networks sit inside a boxed card, and
  /// a bare "Add or manage networks" row (no box, no chevron) sits below it and
  /// opens the Bluetooth provisioning page.
  Widget _buildWifiCard() {
    return Consumer<BleService>(
      builder: (context, ble, _) {
        final saved = ble.savedNetworks;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Boxed saved-networks list ─────────────────────
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: saved.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.wifi_off_rounded,
                                  color: AppColors.textTertiary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No networks saved yet',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]
                    : saved.asMap().entries.map((e) {
                        final ssid = e.value;
                        final isConnected = ssid == ble.connectedSsid;
                        final isLast = e.key == saved.length - 1;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 13),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.wifi_rounded,
                                    color: isConnected
                                        ? AppColors.success
                                        : AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ssid,
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          isConnected ? 'Connected' : 'Saved',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: isConnected
                                                ? AppColors.success
                                                : AppColors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              Container(
                                height: 0.5,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                color: AppColors.glassBorder,
                              ),
                          ],
                        );
                      }).toList(),
              ),
            ),

            const SizedBox(height: 12),

            // ── Bare "Add or manage networks" row (no box, no chevron) ──
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openWifi,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.electricBlue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: AppColors.electricBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Edit network',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Collapsible usage indicator. Collapsed = a bare skinny bar showing the two
  /// remaining counts (silver standard → blue premium). Tapping expands it back
  /// to the original two-column card, and tapping again collapses it.
  /// Bare skinny usage bar: the two remaining counts with small labels, over
  /// a silver standard segment easing into a blue premium one.
  ///
  /// There used to be a second, boxed layout you could tap to swap into. It
  /// showed the same two numbers in a card, so it was a second way to read
  /// one fact — dropped, along with the toggle chevron.
  Widget _buildUsage() {
    return Consumer<CloudService>(
      builder: (context, cloud, _) {
        final isPro = cloud.planType?.toLowerCase() == 'pro';
        const premiumBlue = Color(0xFF9DB6DA);
        const premiumBlueDark = Color(0xFF6E8FBE);

        final sLeft = isPro
            ? -1
            : (cloud.cheapLimit - cloud.cheapUsage)
                .clamp(0, cloud.cheapLimit > 0 ? cloud.cheapLimit : 0);
        final pLeft = isPro
            ? -1
            : (cloud.premiumLimit - cloud.premiumUsage)
                .clamp(0, cloud.premiumLimit > 0 ? cloud.premiumLimit : 0);

        // Widths track what's left, so the bar empties as the day is used up.
        final sFlex = isPro ? 1 : (sLeft > 0 ? sLeft : 1);
        final pFlex = isPro ? 0 : (pLeft > 0 ? pLeft : 1);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _UsageCount(
                    value: isPro ? '∞' : '$sLeft',
                    label: 'Standard',
                    color: AppColors.textPrimary,
                  ),
                  _UsageCount(
                    value: isPro ? '∞' : '$pLeft',
                    label: 'Premium',
                    color: premiumBlue,
                    trailing: true,
                  ),
                ],
              ),
              const SizedBox(height: 9),
              SizedBox(
                height: 10,
                child: Row(
                  children: [
                    Expanded(
                      flex: sFlex,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE8E8F0), AppColors.electricBlue],
                          ),
                        ),
                      ),
                    ),
                    if (!isPro) const SizedBox(width: 4),
                    if (!isPro)
                      Expanded(
                        flex: pFlex,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: const LinearGradient(
                              colors: [
                                AppColors.electricBlue,
                                premiumBlue,
                                premiumBlueDark,
                              ],
                              stops: [0.0, 0.6, 1.0],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLastPromptCard() {
    return Consumer<CloudService>(
      builder: (context, cloud, _) {
        if (cloud.history.isEmpty) {
          return GlassCard(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: AppColors.textTertiary,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No prompts yet',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use CalcAI on your calculator to see activity here',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textTertiary.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final last = cloud.history.first;
        final isImage = (last['type'] ?? '').toString().contains('image');
        // For photos the logged prompt is the auto instruction, so label it
        // "Photo" instead of surfacing that text.
        final question = isImage
            ? 'Photo'
            : (last['question'] ?? last['prompt'] ?? '').toString();
        final response = latexToReadable((last['response'] ?? '').toString());
        final imageUrl = safeImageUrl(last['imageUrl']?.toString());

        return GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo thumbnail if it's an image entry
              if (isImage && imageUrl != null)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isImage
                              ? Icons.camera_alt_rounded
                              : Icons.auto_awesome_rounded,
                          color: AppColors.electricBlue,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Latest Activity',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (question.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        question,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (response.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        response,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showModelPicker(CloudService cloud) {
    final providers = [
      _ModelProvider('OpenAI', Icons.auto_awesome_rounded, [
        'gpt-5', 'gpt-5-mini',
      ]),
      _ModelProvider('Google', Icons.cloud_rounded, [
        'gemini-3.1-pro-preview', 'gemini-3.5-flash', 'gemini-3.1-flash-lite',
      ]),
      _ModelProvider('Anthropic', Icons.psychology_rounded, [
        'claude-opus-4-8', 'claude-sonnet-4-6', 'claude-haiku-4-5',
      ]),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ModelPickerSheet(
        providers: providers,
        currentModel: cloud.currentModel,
        onSelected: (model) {
          Navigator.pop(ctx);
          _setModel(model);
        },
      ),
    );
  }

  Future<void> _setModel(String model) async {
    setState(() => _isLoadingModel = true);
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    if (auth.token != null && auth.primaryMac != null) {
      await cloud.setModel(
          auth.token!, auth.primaryMac!, model, cloud.responseStyle);
    }
    if (mounted) setState(() => _isLoadingModel = false);
  }

  Future<void> _setStyle(String style) async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    if (auth.token != null && auth.primaryMac != null) {
      await cloud.setModel(auth.token!, auth.primaryMac!,
          cloud.currentModel ?? 'gpt-5-mini', style);
    }
  }
}

// ── Model Picker ────────────────────────────────────────────────────────

class _ModelProvider {
  final String name;
  final IconData icon;
  final List<String> models;
  const _ModelProvider(this.name, this.icon, this.models);
}

class _ModelPickerSheet extends StatefulWidget {
  final List<_ModelProvider> providers;
  final String? currentModel;
  final ValueChanged<String> onSelected;

  const _ModelPickerSheet({
    required this.providers,
    required this.currentModel,
    required this.onSelected,
  });

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    // Auto-select tab based on current model
    if (widget.currentModel != null) {
      for (int i = 0; i < widget.providers.length; i++) {
        if (widget.providers[i].models.contains(widget.currentModel)) {
          _selectedTab = i;
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.providers[_selectedTab];

    return Container(
      height: MediaQuery.of(context).size.height * 0.5,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.glassBorder, width: 0.5),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text(
              'Select AI Model',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // ── Provider tabs ──────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: List.generate(widget.providers.length, (i) {
                final p = widget.providers[i];
                final isActive = i == _selectedTab;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTab = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.electricBlue.withOpacity(0.12)
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? AppColors.electricBlue.withOpacity(0.3)
                              : Colors.transparent,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            p.icon,
                            size: 20,
                            color: isActive
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            p.name,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 16),

          // ── Model list for selected provider ───────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: provider.models.length,
              itemBuilder: (context, index) {
                final model = provider.models[index];
                final isSelected = model == widget.currentModel;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onSelected(model),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.electricBlue.withOpacity(0.1)
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.electricBlue.withOpacity(0.3)
                                : AppColors.glassBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                model,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            _TierTag(free: isFreeModel(model)),
                            const SizedBox(width: 10),
                            if (isSelected)
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.success.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.success,
                                  size: 16,
                                ),
                              )
                            else
                              const SizedBox(width: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Premium" tag (star) shown next to premium models. Free models get no tag.
class _TierTag extends StatelessWidget {
  final bool free;
  const _TierTag({required this.free});

  @override
  Widget build(BuildContext context) {
    if (free) return const SizedBox.shrink();
    // Whitish → blue gradient pill, matching the premium end of the usage bar.
    const textColor = Color(0xFF2F4E75);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          colors: [Color(0xFFE8E8F0), Color(0xFF9DB6DA)],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 11, color: textColor),
          const SizedBox(width: 3),
          Text(
            'Premium',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// One side of the usage bar: the number with a small label beneath it.
class _UsageCount extends StatelessWidget {
  const _UsageCount({
    required this.value,
    required this.label,
    required this.color,
    this.trailing = false,
  });

  final String value;
  final String label;
  final Color color;

  /// Right-hand side of the bar, so the text aligns to its own edge.
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          trailing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
