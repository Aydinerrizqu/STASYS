import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/session_logger.dart';
import '../session_detail_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Training Sessions'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            onPressed: () => _showAboutDialog(context),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats Overview Card
          _buildStatsOverview(),
          
          // Sessions List
          Expanded(
            child: _buildSessionsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _refreshSessions(context),
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildStatsOverview() {
    return Consumer<SessionProvider>(
      builder: (context, sessionProvider, child) {
        final sessions = sessionProvider.sessions;
        
        if (sessions.isEmpty) {
          return const SizedBox.shrink();
        }

        // Calculate stats
        int totalSessions = sessions.length;
        double totalDuration = sessions.fold(0.0, (sum, session) => sum + session.duration);
        double avgDuration = totalDuration / totalSessions;
        
        // Find latest session
        //SessionLog latestSession = sessions.first;
        
        return Card(
          margin: const EdgeInsets.all(16),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics, color: Colors.blue, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Training Overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Stats Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        'Total Sessions',
                        totalSessions.toString(),
                        Icons.fitness_center,
                        Colors.green,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        'Total Duration',
                        '${(totalDuration / 60).toStringAsFixed(1)} min',
                        Icons.timer,
                        Colors.orange,
                      ),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        'Avg Duration',
                        '${avgDuration.toStringAsFixed(1)}s',
                        Icons.speed,
                        Colors.purple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionsList() {
    return Consumer<SessionProvider>(
      builder: (context, sessionProvider, child) {
        // Sort sessions by date (newest first)
        final sortedSessions = sessionProvider.sessions
            .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

        if (sortedSessions.isEmpty) {
          return Center(
            child: Text(
              'No sessions recorded yet',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: sortedSessions.length,
          itemBuilder: (context, index) {
            final session = sortedSessions[index];
            final sessionNumber = sortedSessions.length - index;
            final formattedTime = '${session.date.hour}:${session.date.minute.toString().padLeft(2, '0')}';
            final formattedDate = '${session.date.day}/${session.date.month}/${session.date.year}';
            
            return GestureDetector(
              onLongPress: () => _showDeleteDialog(context, sessionProvider, session),
              child: ListTile(
                leading: Icon(Icons.analytics, color: Colors.blue),
                title: Text('Session $sessionNumber - $formattedTime'),
                subtitle: Text(formattedDate),
                trailing: Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SessionDetailScreen(session: session),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context, SessionProvider sessionProvider, SessionLog session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Session?'),
        content: Text('Are you sure you want to delete this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              sessionProvider.deleteSession(session);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Session deleted')),
              );
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('About STASYS'),
        content: Text('Sports Training Analysis System v1.0'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _refreshSessions(BuildContext context) {
    final sessionProvider = Provider.of<SessionProvider>(context, listen: false);
    sessionProvider.loadSessions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sessions refreshed')),
    );
  }
}