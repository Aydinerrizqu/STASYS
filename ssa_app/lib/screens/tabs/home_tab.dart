// ============================================
// File: screens/tabs/home_tab.dart
// Home Dashboard — redesigned dark theme
// ============================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/session_provider.dart';
import '../../providers/session_logger.dart';
import '../../theme/app_theme.dart';
import '../session_detail_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Consumer<SessionProvider>(
          builder: (context, sessionProvider, child) {
            final sessions = sessionProvider.sessions;
            final sorted = sessions.toList()
              ..sort((a, b) => b.date.compareTo(a.date));

            return CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(child: _buildHeader(context)),

                // Stats cards
                SliverToBoxAdapter(child: _buildStatsCards(sessions)),

                // Section title
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'RECENT SESSIONS',
                          style: AppTheme.label,
                        ),
                        if (sessions.isNotEmpty)
                          Text(
                            '${sessions.length} total',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Sessions list
                if (sorted.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildSessionCard(
                          context,
                          sorted[index],
                          sessionProvider,
                          index,
                        ),
                        childCount: sorted.length,
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good Morning'
        : now.hour < 17 ? 'Good Afternoon' : 'Good Evening';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.7)],
                ).createShader(bounds),
                child: const Text(
                  'STASYS',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _showAboutDialog(context),
                icon: Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$greeting, Shooter',
            style: AppTheme.subtitle,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(List<SessionLog> sessions) {
    if (sessions.isEmpty) return const SizedBox(height: 16);

    int totalSessions = sessions.length;
    double totalDuration = sessions.fold(0.0, (sum, s) => sum + s.duration);
    double avgScore = sessions.isNotEmpty
        ? sessions.map((s) => s.averageScore).reduce((a, b) => a + b) / sessions.length
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.fitness_center,
              iconColor: AppTheme.primary,
              value: '$totalSessions',
              label: 'Sessions',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.timer_outlined,
              iconColor: AppTheme.secondary,
              value: _formatDuration(totalDuration),
              label: 'Total Time',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.star_outline,
              iconColor: AppTheme.getScoreColor(avgScore),
              value: avgScore > 0 ? '${avgScore.toInt()}' : '--',
              label: 'Avg Score',
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    if (seconds < 60) return '${seconds.toInt()}s';
    if (seconds < 3600) return '${(seconds / 60).toInt()}m';
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    return '${h}h ${m}m';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.track_changes_outlined,
              size: 36,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Sessions Yet',
            style: AppTheme.title.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your STASYS device and start training',
            style: AppTheme.subtitle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    SessionLog session,
    SessionProvider provider,
    int index,
  ) {
    final avgScore = session.averageScore;
    final scoreColor = AppTheme.getScoreColor(avgScore);
    final scoreLabel = AppTheme.getScoreLabel(avgScore);
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('HH:mm');

    return Dismissible(
      key: Key(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: AppTheme.error),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Session?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete', style: TextStyle(color: AppTheme.error)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (direction) {
        provider.deleteSession(session);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session deleted')),
        );
      },
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionDetailScreen(session: session),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Row(
            children: [
              // Score circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scoreColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        avgScore > 0 ? '${avgScore.toInt()}' : '--',
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (avgScore > 0)
                        Text(
                          scoreLabel.substring(0, 1),
                          style: TextStyle(
                            color: scoreColor.withValues(alpha: 0.7),
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Session info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateFormat.format(session.date),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildMiniChip(Icons.access_time, timeFormat.format(session.date)),
                        const SizedBox(width: 8),
                        _buildMiniChip(Icons.timer_outlined, '${session.duration.toStringAsFixed(0)}s'),
                        const SizedBox(width: 8),
                        _buildMiniChip(
                          Icons.gps_fixed,
                          session.firearmType.displayName,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.chevron_right,
                color: AppTheme.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppTheme.textTertiary),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.7)],
          ).createShader(bounds),
          child: const Text(
            'STASYS',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shooter Stability Analysis System',
              style: AppTheme.subtitle,
            ),
            const SizedBox(height: 12),
            Text('Version 3.1', style: AppTheme.body),
            const SizedBox(height: 4),
            Text(
              'DIY dry/live fire training with shot scoring',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Stat Card Widget
// ============================================
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
