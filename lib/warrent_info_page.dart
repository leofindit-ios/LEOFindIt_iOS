import 'package:flutter/material.dart';

class WarrantInfoPage extends StatelessWidget {
  const WarrantInfoPage({super.key});

  // The UI of the warrant info page
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Warrant Info')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Warrant Info',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Text(
            'Placeholder Text',
          ),
        ],
      ),
    );
  }
}