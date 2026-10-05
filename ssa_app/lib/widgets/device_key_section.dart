import 'package:flutter/material.dart';

import '../services/device_key_store.dart';
import '../theme/app_theme.dart';

/// Settings section for managing the firmware-v2 device key.
///
/// The key itself is never displayed — only an obfuscated input while editing
/// and a "CONFIGURED" confirmation state once stored in secure storage.
class DeviceKeySection extends StatefulWidget {
  const DeviceKeySection({super.key, this.keyStore});

  /// Injectable for tests; defaults to production secure storage.
  final DeviceKeyStore? keyStore;

  @override
  State<DeviceKeySection> createState() => _DeviceKeySectionState();
}

class _DeviceKeySectionState extends State<DeviceKeySection> {
  late final DeviceKeyStore _store;
  final TextEditingController _controller = TextEditingController();
  bool _obscured = true;
  bool _hasKey = false;
  bool _busy = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _store = widget.keyStore ?? DeviceKeyStore();
    _loadStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final key = await _store.readKey();
      if (mounted) setState(() => _hasKey = key != null);
    } catch (_) {
      // Secure storage unavailable — present the entry state.
      if (mounted) setState(() => _hasKey = false);
    }
  }

  Future<void> _save() async {
    final text = _controller.text;
    try {
      DeviceKeyStore.parseHexKey(text);
    } on FormatException catch (e) {
      setState(() => _errorText = e.message);
      return;
    }

    setState(() {
      _errorText = null;
      _busy = true;
    });
    try {
      await _store.saveKey(text);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _hasKey = true;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Keep the entered text so the user can retry.
      setState(() => _busy = false);
      _showSnack('Could not save device key.');
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await _store.deleteKey();
      if (!mounted) return;
      setState(() {
        _hasKey = false;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('Could not remove device key.');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'DEVICE KEY',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: StsysTheme.cyanOf(context),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StsysTheme.surfaceContainerLowOf(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _hasKey ? _buildConfigured(context) : _buildEntry(context),
        ),
      ],
    );
  }

  Widget _buildEntry(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          obscureText: _obscured,
          onChanged: (_) {
            if (_errorText != null) setState(() => _errorText = null);
          },
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: StsysTheme.onSurfaceOf(context),
          ),
          decoration: InputDecoration(
            hintText: '64-character hex key',
            hintStyle: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.35),
            ),
            errorText: _errorText,
            errorMaxLines: 2,
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(
                _obscured ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: StsysTheme.onSurfaceOf(context).withValues(alpha: 0.5),
              ),
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: _busy ? null : _save,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: StsysTheme.brandGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'SAVE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: StsysTheme.onPrimaryOf(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigured(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.verified,
          size: 20,
          color: StsysTheme.cyanOf(context),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CONFIGURED',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: StsysTheme.onSurfaceOf(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Key stored in secure storage',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  color: StsysTheme.onSurfaceOf(context)
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _busy ? null : _remove,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: StsysTheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: StsysTheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'REMOVE',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: StsysTheme.error,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
