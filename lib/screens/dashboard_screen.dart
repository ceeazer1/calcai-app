import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';

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
    final auth = context.watch<AuthService>();
    final hasDevice = auth.primaryMac != null && auth.primaryMac!.isNotEmpty;

    Widget dashboardContent = ListView(
      physics: hasDevice
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        _buildDeviceCard(),
        const SizedBox(height: 16),
        _buildSectionTitle('AI Configuration'),
        const SizedBox(height: 12),
        _buildModelSelector(),
        const SizedBox(height: 12),
        _buildThinkingSelector(),
        const SizedBox(height: 24),
        _buildSectionTitle('Usage'),
        const SizedBox(height: 12),
        _buildUsageCard(),
        const SizedBox(height: 24),
        _buildSectionTitle('Recent Activity'),
        const SizedBox(height: 12),
        _buildLastPromptCard(),
      ],
    );

    if (hasDevice) {
      dashboardContent = RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.electricBlue,
        backgroundColor: AppColors.surface,
        child: dashboardContent,
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.backgroundGradient,
      ),
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Stack(
            children: [
              // ── Dashboard content ──────────────────────────
              IgnorePointer(
                ignoring: !hasDevice,
                child: dashboardContent,
              ),

              // ── Dark overlay + floating connect card ───────
              if (!hasDevice) ...[
                // Dim overlay
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                  ),
                ),
                // Floating connect card
                Positioned(
                  left: 20,
                  right: 20,
                  top: 80,
                  child: GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.electricBlue.withOpacity(0.15),
                                ),
                                child: const Icon(
                                  Icons.calculate_rounded,
                                  color: AppColors.electricBlue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'No CalcAI device linked',
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Link your CalcAI to access settings and activity',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                SwitchToWifiTabNotification().dispatch(context);
                              },
                              icon: const Icon(Icons.add_link_rounded, size: 18),
                              label: Text(
                                'Link Your Device',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.electricBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        ShaderMask(
          shaderCallback: (bounds) =>
              AppColors.accentGradient.createShader(bounds),
          child: Text(
            'CalcAI',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.success.withOpacity(0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Online',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard() {
    return Consumer<CloudService>(
      builder: (context, cloud, _) {
        final auth = context.read<AuthService>();
        return GlassCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Calculator icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradientSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.calculate_rounded,
                  color: AppColors.textPrimary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${auth.username ?? 'My'}'s CalcAI",
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      auth.primaryMac ?? 'No device paired',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.electricBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cloud.planType ?? 'Free',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.electricBlue,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
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

  Widget _buildThinkingSelector() {
    return Consumer<CloudService>(
      builder: (context, cloud, _) {
        final levels = ['off', 'low', 'medium', 'high'];
        final current = cloud.thinkingLevel ?? 'off';

        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.psychology_rounded,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Thinking Level',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: levels.map((level) {
                  final isSelected = level == current;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _setThinking(level),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(
                          right: level != 'high' ? 8 : 0,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.electricBlue.withOpacity(0.15)
                              : AppColors.surfaceHighlight.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.electricBlue.withOpacity(0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            level[0].toUpperCase() + level.substring(1),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsageCard() {
    return Consumer<CloudService>(
      builder: (context, cloud, _) {
        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _UsageStat(
                label: 'Standard',
                value: '${cloud.cheapUsage ?? 0}',
                limit: cloud.planType == 'Pro' ? '∞' : '/30',
                color: AppColors.success,
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.glassBorder,
              ),
              _UsageStat(
                label: 'Premium',
                value: '${cloud.premiumUsage ?? 0}',
                limit: cloud.planType == 'Pro' ? '∞' : '/10',
                color: AppColors.warning,
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
        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.electricBlue,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Latest Prompt',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                last['prompt']?.toString() ?? '',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                last['answer']?.toString() ?? '',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
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
        'gpt-5.5', 'gpt-5.5-instant', 'gpt-5.4-pro', 'gpt-5.4',
        'gpt-5.4-mini', 'gpt-5.4-nano', 'o4-mini',
      ]),
      _ModelProvider('Google', Icons.cloud_rounded, [
        'gemini-3.5-flash', 'gemini-3.1-pro', 'gemini-3.1-flash-lite',
        'gemini-2.5-pro', 'gemini-2.5-flash',
      ]),
      _ModelProvider('Anthropic', Icons.psychology_rounded, [
        'claude-opus-4.8', 'claude-opus-4.7', 'claude-opus-4.6',
        'claude-sonnet-4.6', 'claude-sonnet-4.5', 'claude-haiku-4.5',
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
      await cloud.setModel(auth.token!, auth.primaryMac!, model,
          cloud.thinkingLevel ?? 'off');
    }
    if (mounted) setState(() => _isLoadingModel = false);
  }

  Future<void> _setThinking(String level) async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    if (auth.token != null && auth.primaryMac != null) {
      await cloud.setModel(auth.token!, auth.primaryMac!,
          cloud.currentModel ?? 'gpt-5.4-mini', level);
    }
  }
}

class _UsageStat extends StatelessWidget {
  final String label;
  final String value;
  final String limit;
  final Color color;

  const _UsageStat({
    required this.label,
    required this.value,
    required this.limit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                TextSpan(
                  text: limit,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
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
      height: MediaQuery.of(context).size.height * 0.65,
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
                              ),
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
