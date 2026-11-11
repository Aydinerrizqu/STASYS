import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/ota_provider.dart';

class OtaUpdateScreen extends StatefulWidget {
  const OtaUpdateScreen({super.key});

  @override
  State<OtaUpdateScreen> createState() => _OtaUpdateScreenState();
}

class _OtaUpdateScreenState extends State<OtaUpdateScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-start OTA when screen is shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ota = context.read<OtaProvider>();
      if (ota.state == OtaState.idle) {
        ota.startOta();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StsysTheme.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: StsysTheme.backgroundOf(context),
        elevation: 0,
        title: Text(
          'Firmware Update',
          style: TextStyle(
            color: StsysTheme.onSurfaceOf(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.close, color: StsysTheme.onSurfaceOf(context)),
          onPressed: () {
            context.read<OtaProvider>().reset();
            context.go('/connection');
          },
        ),
      ),
      body: Consumer<OtaProvider>(
        builder: (context, ota, _) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // Circular progress
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Background circle
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: null,
                          strokeWidth: 10,
                          backgroundColor: StsysTheme.surfaceContainerHighOf(context),
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF2A2A2A)),
                        ),
                      ),
                      // Progress circle
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: ota.progress,
                          strokeWidth: 10,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6B3D)),
                        ),
                      ),
                      // Percentage + chunks
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(ota.progress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Color(0xFFFF6B3D),
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (ota.totalChunks > 0)
                            Text(
                              '${ota.sentChunks}/${ota.totalChunks} chunks',
                              style: TextStyle(
                                color: StsysTheme.onSurfaceVariantOf(context),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                // Status message
                Text(
                  ota.statusMessage,
                  style: TextStyle(color: StsysTheme.onSurfaceVariantOf(context), fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Step indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stepIndicator('Transfer', ota.state == OtaState.sending),
                    _dot(),
                    _stepIndicator('Verify', ota.state == OtaState.verifying),
                    _dot(),
                    _stepIndicator('Flash', ota.state == OtaState.rebooting),
                  ],
                ),
                const Spacer(flex: 3),
                // Error state
                if (ota.state == OtaState.failed) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          'Update Gagal',
                          style: TextStyle(
                            color: StsysTheme.onSurfaceOf(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ota.errorMessage,
                          style: TextStyle(color: StsysTheme.onSurfaceVariantOf(context), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.go('/connection'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: StsysTheme.onSurfaceVariantOf(context),
                            side: BorderSide(color: StsysTheme.outlineVariantOf(context)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<OtaProvider>().reset();
                            context.read<OtaProvider>().startOta();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B3D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                ],
                // Success state
                if (ota.state == OtaState.completed) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 32),
                        SizedBox(height: 8),
                        Text(
                          'Update Berhasil!',
                          style: TextStyle(
                            color: StsysTheme.onSurfaceOf(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Firmware berhasil di-update. Koneksi ulang...',
                          style: TextStyle(color: StsysTheme.onSurfaceVariantOf(context), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => context.go('/connection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B3D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Lanjutkan'),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stepIndicator(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFF6B3D).withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? const Color(0xFFFF6B3D) : const Color(0xFF444444),
          fontSize: 13,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _dot() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '•',
        style: TextStyle(color: Color(0xFF2A2A2A), fontSize: 14),
      ),
    );
  }
}
