import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class OtaPromptDialog extends StatelessWidget {
  final String currentVersion;
  final String newVersion;
  final VoidCallback onUpdate;
  final VoidCallback? onSkip;

  const OtaPromptDialog({
    super.key,
    required this.currentVersion,
    required this.newVersion,
    required this.onUpdate,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: StsysTheme.surfaceContainerHighOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: StsysTheme.outlineVariantOf(context), width: 1),
      ),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: StsysTheme.primaryOf(context).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.system_update_alt,
              color: StsysTheme.primaryOf(context),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Firmware Update',
            style: TextStyle(
              color: StsysTheme.onSurfaceOf(context),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version $newVersion tersedia untuk STASYS kamu.',
            style: TextStyle(color: StsysTheme.onSurfaceVariantOf(context), fontSize: 14),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: StsysTheme.surfaceContainerLowestOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: StsysTheme.outlineVariantOf(context)),
            ),
            child: Column(
              children: [
                _versionRow(
                  context,
                  'Current',
                  currentVersion,
                  StsysTheme.primaryOf(context),
                ),
                Divider(
                  color: StsysTheme.outlineVariantOf(context),
                  height: 20,
                ),
                _versionRow(
                  context,
                  'New',
                  newVersion,
                  StsysTheme.cyanOf(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StsysTheme.primaryOf(context).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: StsysTheme.primaryOf(context).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: StsysTheme.primaryOf(context),
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Jangan putuskan koneksi Bluetooth saat update berlangsung.',
                    style: TextStyle(color: StsysTheme.onSurfaceVariantOf(context), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (onSkip != null)
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: StsysTheme.onSurfaceVariantOf(context),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Skip'),
          ),
        ElevatedButton(
          onPressed: onUpdate,
          style: ElevatedButton.styleFrom(
            backgroundColor: StsysTheme.primaryOf(context),
            foregroundColor: StsysTheme.onPrimaryOf(context),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Update Now'),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );
  }

  Widget _versionRow(BuildContext context, String label, String version, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: StsysTheme.onSurfaceVariantOf(context), fontSize: 13),
        ),
        Row(
          children: [
            Text(
              'v',
              style: TextStyle(
                color: color.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            Text(
              version,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
