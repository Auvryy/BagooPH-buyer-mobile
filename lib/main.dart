import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'BagooPH Buyer',
      home: Scaffold(body: Center(child: Text('BagooPH Buyer'))),
    );
  }
}
