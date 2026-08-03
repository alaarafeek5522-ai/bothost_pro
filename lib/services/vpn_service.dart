import 'dart:io';
import 'package:flutter/material.dart';

class VPNService {
  static final List<String> _vpnRanges = [
    '10.', '172.16.', '172.17.', '172.18.', '172.19.',
    '172.20.', '172.21.', '172.22.', '172.23.', '172.24.',
    '172.25.', '172.26.', '172.27.', '172.28.', '172.29.',
    '172.30.', '172.31.', '192.168.',
  ];

  static Future<bool> isVPNActive() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          for (final range in _vpnRanges) {
            if (ip.startsWith(range)) {
              // Could be VPN or local network - need better detection
            }
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static void showVPNDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_lock, color: Color(0xFFE94560)),
            SizedBox(width: 10),
            Text('⚠️ VPN مفعل'),
          ],
        ),
        content: const Text(
          'التطبيق مش بيشتغل مع VPN.\n\n'
          'لو شغال VPN، اطفيه وجرب تاني.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }
}
