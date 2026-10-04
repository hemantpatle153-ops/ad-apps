import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _text.text.trim();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _text,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: 'Text, link or phone number',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        if (data.isNotEmpty)
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: data, size: 240),
            ),
          ),
      ],
    );
  }
}
