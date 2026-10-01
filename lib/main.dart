import 'dart:convert';

import 'package:flutter/material.dart';

void main() {
  runApp(const BabyCryTranslatorApp());
}

class BabyCryTranslatorApp extends StatelessWidget {
  const BabyCryTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '아기 언어 번역기',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        useMaterial3: true,
      ),
      home: const TranslatorScreen(),
    );
  }
}

class CryData {
  final String soundType;
  final DateTime timestamp;

  CryData({required this.soundType, required this.timestamp});

  factory CryData.fromJson(Map<String, dynamic> json) {
    return CryData(
      soundType: json['soundType'] as String? ?? 'unknown',
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class TranslationResult {
  final String cause;
  final String tip;
  final IconData icon;

  const TranslationResult(this.cause, this.tip, this.icon);
}

class CryTranslator {
  static TranslationResult translate(String soundType) {
    switch (soundType.toLowerCase()) {
      case 'neh':
        return const TranslationResult('배고픔 (Neh)', '수유를 준비해 주세요. 아기에게 젖이나 젖병을 물리세요.', Icons.restaurant_menu);
      case 'owh':
        return const TranslationResult('졸림 (Owh)', '아기를 재울 시간입니다. 주변을 어둡게 하고 안락하게 안아주세요.', Icons.bedtime);
      case 'heh':
        return const TranslationResult('불편함 (Heh)', '기저귀가 젖었거나 옷이 불편한지, 너무 덥거나 춥지 않은지 확인해 주세요.', Icons.child_care);
      case 'eairh':
        return const TranslationResult('배에 가스가 참 (Eairh)', '아기의 배를 부드럽게 마사지하거나 하늘 자전거 타기 운동을 시켜주세요.', Icons.healing);
      case 'eh':
        return const TranslationResult('트림 필요 (Eh)', '수유 후라면 아기를 안고 등을 가볍게 토닥여 트림을 시켜주세요.', Icons.air);
      default:
        return const TranslationResult('분석 대기 중', '아기의 울음소리를 듣고 있습니다...', Icons.hearing);
    }
  }
}

class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({super.key});

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen> {
  TranslationResult? _currentResult;

  void _simulateHardwareInput(String simulatedJson) {
    try {
      final parsedJson = jsonDecode(simulatedJson) as Map<String, dynamic>;
      final cryData = CryData.fromJson(parsedJson);
      setState(() => _currentResult = CryTranslator.translate(cryData.soundType));
    } on FormatException catch (error) {
      debugPrint('JSON 파싱 에러: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _currentResult;
    return Scaffold(
      appBar: AppBar(
        title: const Text('아기 언어 번역기', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('실시간 분석 결과', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(result?.icon ?? Icons.mic_none, size: 90, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 24),
                      Text(result?.cause ?? '하드웨어 대기 중', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      Text(result?.tip ?? '기기와 연동되어 데이터가 수신되면\n여기에 번역 결과와 대처 방법이 나타납니다.', style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.5), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  const Text('하드웨어 수신 테스트 (JSON 시뮬레이션)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    _buildTestButton('배고픔(Neh)', 'neh'),
                    _buildTestButton('졸림(Owh)', 'owh'),
                    _buildTestButton('불편함(Heh)', 'heh'),
                    _buildTestButton('가스(Eairh)', 'eairh'),
                    _buildTestButton('트림(Eh)', 'eh'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestButton(String label, String soundType) {
    return ElevatedButton(
      onPressed: () => _simulateHardwareInput(jsonEncode({
        'soundType': soundType,
        'timestamp': DateTime.now().toIso8601String(),
      })),
      child: Text(label),
    );
  }
}
