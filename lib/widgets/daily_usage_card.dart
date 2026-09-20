import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../services/usage_tracker.dart';
import '../theme/app_colors.dart';

String _timezoneLabel(DateTime localTime) {
  final name = localTime.timeZoneName.trim();
  if (RegExp(r'^[A-Z]{2,6}$').hasMatch(name)) return name;
  // Some platforms return the English long name instead of EDT, PST, etc.
  if (RegExp(r'^[A-Za-z ]+ Time$').hasMatch(name)) {
    return name
        .split(RegExp(r'\s+'))
        .map((word) => word[0])
        .join()
        .toUpperCase();
  }
  // Use an accurate offset when a localized name has no reliable abbreviation.
  final offset = localTime.timeZoneOffset.inMinutes;
  if (offset == 0) return 'UTC';
  final hours = offset.abs() ~/ 60;
  final minutes = (offset.abs() % 60).toString().padLeft(2, '0');
  return 'UTC${offset < 0 ? '-' : '+'}$hours:$minutes';
}

class DailyUsageCard extends StatefulWidget {
  const DailyUsageCard({super.key, this.active = true});
  final bool active;
  @override
  State<DailyUsageCard> createState() => _DailyUsageCardState();
}

class _DailyUsageCardState extends State<DailyUsageCard>
    with WidgetsBindingObserver {
  Timer? _clock;
  late CloudService _cloud;
  bool _foreground = true;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _cloud = context.read<CloudService>();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateVisibility();
      _refresh();
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        _updateVisibility();
        if (_visible && mounted) setState(() {});
      });
    });
  }

  void _updateVisibility() {
    if (!mounted) return;
    final box = context.findRenderObject();
    var visible =
        widget.active &&
        _foreground &&
        ModalRoute.of(context)?.isCurrent != false;
    if (box is RenderBox && box.hasSize) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final viewport = Offset.zero & MediaQuery.sizeOf(context);
      visible = visible && rect.overlaps(viewport);
    } else {
      visible = false;
    }
    _visible = visible;
    _cloud.usageTracker.setVisible(visible);
  }

  void _refresh() {
    if (!mounted) return;
    final token = context.read<AuthService>().token;
    if (token != null) unawaited(_cloud.getUsage(token));
  }

  @override
  void didUpdateWidget(DailyUsageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) _cloud.usageTracker.setVisible(false);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateVisibility();
        _refresh();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateVisibility();
    if (_foreground) _refresh();
  }

  @override
  void dispose() {
    _clock?.cancel();
    if (_clock != null) _cloud.usageTracker.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudService>();
    return UsageCardContent(
      tracker: cloud.usageTracker,
      personalProviders: {
        ...?cloud.usageTracker.data?.personalProviders,
        for (final provider in cloud.apiKeys.keys)
          if (cloud.hasApiKey(provider) && cloud.apiKeyEnabled(provider))
            provider,
      },
      onRefresh: _refresh,
    );
  }
}

/// Presentation is independently testable without timers or network calls.
class UsageCardContent extends StatelessWidget {
  const UsageCardContent({
    super.key,
    required this.tracker,
    required this.personalProviders,
    required this.onRefresh,
  });
  final UsageTracker tracker;
  final Set<String> personalProviders;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final data = tracker.data;
    final percent = tracker.expired || tracker.syncing
        ? null
        : data?.remainingPercent;
    final unlimited = data?.unlimited == true && !tracker.expired;
    final exhausted = tracker.exhausted && !tracker.expired && !tracker.syncing;
    final unknown = percent == null && !unlimited && !exhausted;
    final stale = tracker.stale;
    final failure = tracker.failure;
    final headline = failure == UsageFailure.session
        ? 'Sign in to view usage'
        : failure == UsageFailure.forbidden
        ? 'Usage access unavailable'
        : unlimited
        ? 'Unlimited'
        : exhausted
        ? 'Daily allowance used'
        : percent != null
        ? '${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 1)}% left'
        : tracker.syncing || data != null
        ? 'Updating usage'
        : failure == UsageFailure.offline
        ? 'Usage unavailable offline'
        : failure != null
        ? 'Usage temporarily unavailable'
        : 'Loading usage';
    final low = !stale && (exhausted || (percent != null && percent <= 20));
    final tint = low ? const Color(0xFFD6B48B) : const Color(0xFFBFCDE3);
    final reset = tracker.resetsAt?.toLocal();
    final resetTime = reset == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(reset),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    headline,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: stale
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (unlimited)
                const Icon(
                  Icons.all_inclusive_rounded,
                  color: AppColors.textSecondary,
                )
              else if (unknown)
                Semantics(
                  label: headline,
                  child: ExcludeSemantics(
                    child: LinearProgressIndicator(
                      // Reduced motion keeps the placeholder static without inventing a balance.
                      value:
                          MediaQuery.disableAnimationsOf(context) ||
                              failure != null
                          ? 0
                          : null,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                      backgroundColor: AppColors.surfaceLight,
                      color: tint,
                    ),
                  ),
                )
              else
                Semantics(
                  label: stale
                      ? 'Last known daily AI allowance, out of date'
                      : 'Daily AI allowance',
                  value: exhausted ? '0 percent left' : '$percent percent left',
                  child: SizedBox(
                    height: 10,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        if (!exhausted && percent! > 0)
                          FractionallySizedBox(
                            widthFactor: percent / 100,
                            heightFactor: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: LinearGradient(
                                  colors: stale
                                      ? [
                                          AppColors.textTertiary,
                                          AppColors.textSecondary,
                                        ]
                                      : low
                                      ? [
                                          const Color(0xFFAB805B),
                                          const Color(0xFFF2D2A8),
                                        ]
                                      : [
                                          const Color(0xFF8E9CB8),
                                          const Color(0xFFC9D6F2),
                                          const Color(0xFFF4F7FF),
                                        ],
                                ),
                                boxShadow: stale
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: tint.withValues(alpha: 0.35),
                                          blurRadius: 18,
                                          spreadRadius: 1,
                                        ),
                                        BoxShadow(
                                          color: tint.withValues(alpha: 0.2),
                                          blurRadius: 5,
                                        ),
                                      ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (resetTime != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    tracker.expired
                        ? 'Resetting usage'
                        : 'Resets at $resetTime ${_timezoneLabel(reset!)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              if (stale)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Out of date · Showing last known usage',
                    style: GoogleFonts.inter(fontSize: 12, color: tint),
                  ),
                ),
              if (failure != null)
                TextButton(
                  onPressed: tracker.loading ? null : onRefresh,
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
        if (personalProviders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.key_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Using your own API key',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${personalProviders.map((p) => switch (p) {
                          'openai' => 'OpenAI',
                          'anthropic' => 'Anthropic',
                          'gemini' || 'google' => 'Google',
                          _ => p,
                        }).join(', ')} usage is billed separately and does not consume your CalcAI allowance. Other providers still use it.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
