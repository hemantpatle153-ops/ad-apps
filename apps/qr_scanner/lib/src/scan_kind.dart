import 'package:flutter/material.dart';

/// What a scanned value looks like, so the result screen can offer the
/// right action (open, pay, join Wi-Fi, call...).
enum ScanKind {
  url(Icons.link, 'Link'),
  upi(Icons.currency_rupee, 'UPI payment'),
  wifi(Icons.wifi, 'Wi-Fi'),
  phone(Icons.phone, 'Phone number'),
  email(Icons.email, 'Email'),
  text(Icons.notes, 'Text'),
  product(Icons.qr_code_2, 'Product code');

  const ScanKind(this.icon, this.label);

  final IconData icon;
  final String label;

  static ScanKind of(String value) {
    final v = value.trim();
    final lower = v.toLowerCase();
    if (lower.startsWith('upi://')) return ScanKind.upi;
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return ScanKind.url;
    }
    if (lower.startsWith('wifi:')) return ScanKind.wifi;
    if (lower.startsWith('tel:')) return ScanKind.phone;
    if (lower.startsWith('mailto:')) return ScanKind.email;
    if (RegExp(r'^\d{8,14}$').hasMatch(v)) return ScanKind.product;
    return ScanKind.text;
  }

  /// The URI to hand to another app, or null when there is nothing to open.
  static Uri? launchUri(String value) {
    final kind = of(value);
    switch (kind) {
      case ScanKind.url:
      case ScanKind.upi:
      case ScanKind.phone:
      case ScanKind.email:
        return Uri.tryParse(value.trim());
      case ScanKind.product:
        return Uri.https('www.google.com', '/search', {'q': value.trim()});
      case ScanKind.wifi:
      case ScanKind.text:
        return null;
    }
  }
}
