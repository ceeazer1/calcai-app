import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_card.dart';

/// History screen — shows all AI interactions from the calculator,
/// including camera photos and text prompts.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedRange = '24h';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final _ranges = ['10m', '1h', '24h', '72h'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
  }

  Future<void> _loadHistory() async {
    final auth = context.read<AuthService>();
    final cloud = context.read<CloudService>();
    if (auth.token != null && auth.primaryMac != null) {
      await cloud.getHistory(auth.token!, auth.primaryMac!, limit: 50);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Returns the earliest allowed timestamp for the selected range.
  DateTime? _cutoff() {
    final now = DateTime.now();
    switch (_selectedRange) {
      case '10m': return now.subtract(const Duration(minutes: 10));
      case '1h':  return now.subtract(const Duration(hours: 1));
      case '24h': return now.subtract(const Duration(hours: 24));
      case '72h': return now.subtract(const Duration(hours: 72));
      default:    return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text(
                    'History',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _loadHistory,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // ── Search bar ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.glassBorder, width: 0.5),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search prompts...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

            // ── Time range chips ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: _ranges.map((range) {
                  final isSelected = range == _selectedRange;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRange = range),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.electricBlue.withOpacity(0.15)
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.electricBlue.withOpacity(0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          range,
                          style: GoogleFonts.inter(
                            fontSize: 13,
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
                  );
                }).toList(),
              ),
            ),

            // ── History list ──────────────────────────────
            Expanded(
              child: Consumer<CloudService>(
                builder: (context, cloud, _) {
                  if (cloud.isLoading && cloud.history.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.textSecondary),
                      ),
                    );
                  }

                  final cutoff = _cutoff();
                  final q = _searchQuery.toLowerCase();

                  final filtered = cloud.history.where((entry) {
                    // Time range filter using ts (Unix ms)
                    if (cutoff != null) {
                      final ts = _tsOf(entry);
                      if (ts != null && ts.isBefore(cutoff)) return false;
                    }
                    // Search filter
                    if (q.isEmpty) return true;
                    final text = _questionOf(entry).toLowerCase();
                    final resp = (entry['response'] ?? '').toString().toLowerCase();
                    return text.contains(q) || resp.contains(q);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded,
                              color: AppColors.textTertiary, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            cloud.history.isEmpty
                                ? 'No prompts yet'
                                : 'Nothing in this time range',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Use CalcAI on your calculator to see history',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppColors.textTertiary.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _loadHistory,
                    color: AppColors.electricBlue,
                    backgroundColor: AppColors.surface,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _HistoryCard(
                          entry: filtered[index],
                          onTap: () => _showDetail(context, filtered[index]),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> entry) {
    final isImage = _isImageEntry(entry);
    final imageUrl = entry['imageUrl']?.toString();
    final question = _questionOf(entry);
    final response = (entry['response'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.glassBorder, width: 0.5),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  children: [
                    // Image
                    if (isImage && imageUrl != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 200,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.electricBlue,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded,
                                  color: AppColors.textTertiary, size: 32),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Question
                    if (question.isNotEmpty) ...[
                      Text('Prompt',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                            letterSpacing: 0.8,
                          )),
                      const SizedBox(height: 6),
                      Text(question,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                            height: 1.5,
                          )),
                      const SizedBox(height: 20),
                    ],

                    // Response
                    if (response.isNotEmpty) ...[
                      Text('Response',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                            letterSpacing: 0.8,
                          )),
                      const SizedBox(height: 6),
                      Text(response,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.6,
                          )),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

bool _isImageEntry(Map<String, dynamic> e) =>
    (e['type'] ?? '').toString().contains('image');

String _questionOf(Map<String, dynamic> e) {
  // For photos the logged "prompt" is the auto tutor instruction, not the
  // student's own text — don't surface it as their prompt.
  if (_isImageEntry(e)) return '';
  return (e['question'] ?? e['prompt'] ?? '').toString();
}

DateTime? _tsOf(Map<String, dynamic> e) {
  final raw = e['ts'];
  if (raw == null) return null;
  try {
    final ms = raw is int ? raw : int.parse(raw.toString());
    return DateTime.fromMillisecondsSinceEpoch(ms);
  } catch (_) {
    return null;
  }
}

String _timeAgo(Map<String, dynamic> e) {
  final t = _tsOf(e);
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ── History Card ──────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  const _HistoryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isImage = _isImageEntry(entry);
    final imageUrl = entry['imageUrl']?.toString();
    final question = _questionOf(entry);
    final response = (entry['response'] ?? '').toString();
    final model = (entry['model'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image thumbnail ──────────────────────────
            if (isImage && imageUrl != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 180,
                      color: AppColors.surfaceLight,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.electricBlue,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    height: 100,
                    color: AppColors.surfaceLight,
                    child: const Center(
                      child: Icon(Icons.image_not_supported_rounded,
                          color: AppColors.textTertiary, size: 28),
                    ),
                  ),
                ),
              ),

            // ── Text content ─────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta row: icon + time + model
                  Row(
                    children: [
                      Icon(
                        isImage
                            ? Icons.camera_alt_rounded
                            : Icons.chat_bubble_outline_rounded,
                        color: isImage
                            ? AppColors.electricBlue
                            : AppColors.textTertiary,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _timeAgo(entry),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (model.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighlight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            model,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Title: the student's prompt, or "Photo" for image entries.
                  if (question.isNotEmpty || isImage) ...[
                    const SizedBox(height: 8),
                    Text(
                      isImage ? 'Photo' : question,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: isImage ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // Response preview
                  if (response.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      response,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                      maxLines: isImage ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
