import 'package:flutter/material.dart';
import '../models/data_models.dart';

// ============================================
// SHOT HISTORY LIST
// ============================================
class ShotHistoryList extends StatelessWidget {
  final List<ShotResult> shots;
  final ShotResult? selectedShot;
  final void Function(ShotResult) onShotSelected;
  final Color Function(double) getScoreColor;
  final String Function(DateTime) formatTime;
  final String Function(double) formatScore;

  const ShotHistoryList({
    super.key,
    required this.shots,
    required this.selectedShot,
    required this.onShotSelected,
    required this.getScoreColor,
    required this.formatTime,
    required this.formatScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Text(
                  'SESSION HISTORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                _buildStats(shots),
              ],
            ),
          ),
          // Shot cards
          Expanded(
            child: ListView.builder(
              itemCount: shots.length,
              itemBuilder: (context, index) {
                final i = shots.length - 1 - index; // Most recent first
                final shot = shots[i];
                final isSelected = shot == selectedShot;
                return ShotCard(
                  shot: shot,
                  shotNumber: i + 1,
                  isSelected: isSelected,
                  onTap: () => onShotSelected(shot),
                  getScoreColor: getScoreColor,
                  formatTime: formatTime,
                  prevShot: i > 0 ? shots[i - 1] : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(List<ShotResult> shots) {
    if (shots.isEmpty) return const SizedBox.shrink();
    final avg = shots.map((s) => s.totalScore).reduce((a, b) => a + b) / shots.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${shots.length} shots | Avg: ${avg.toStringAsFixed(1)}',
        style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ============================================
// SHOT CARD
// ============================================
class ShotCard extends StatelessWidget {
  final ShotResult shot;
  final int shotNumber;
  final bool isSelected;
  final VoidCallback onTap;
  final Color Function(double) getScoreColor;
  final String Function(DateTime) formatTime;
  final ShotResult? prevShot;

  const ShotCard({
    super.key,
    required this.shot,
    required this.shotNumber,
    required this.isSelected,
    required this.onTap,
    required this.getScoreColor,
    required this.formatTime,
    this.prevShot,
  });

  @override
  Widget build(BuildContext context) {
    final scoreColor = getScoreColor(shot.totalScore);
    final split = prevShot != null
        ? shot.timestamp.difference(prevShot!.timestamp).inMilliseconds
        : 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[200]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Shot number
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$shotNumber',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Time
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatTime(shot.timestamp),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'H:${shot.holdScore.toInt()} P:${shot.pressScore.toInt()} R:${shot.recoilScore.toInt()}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            // Split
            if (split > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: split < 1500
                      ? Colors.green.withValues(alpha: 0.1)
                      : split > 3000
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(split / 1000).toStringAsFixed(2)}s',
                  style: TextStyle(
                    fontSize: 11,
                    color: split < 1500
                        ? Colors.green
                        : split > 3000
                            ? Colors.red
                            : Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // Score
            Container(
              width: 48,
              height: 32,
              decoration: BoxDecoration(
                color: scoreColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  shot.totalScore.toInt().toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
