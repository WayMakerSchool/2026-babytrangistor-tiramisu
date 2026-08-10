import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/app_state.dart';
import '../theme.dart';

/// 설정 화면: 연결 방식(데모/MQTT/WebSocket), 기기 정보, 접근성 알림.
class SettingsScreen extends StatefulWidget {
  final AppState appState;
  const SettingsScreen({super.key, required this.appState});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ConnectionMode _mode;
  late bool _vibration;
  late bool _flash;
  late double _threshold;
  late final TextEditingController _mqttHostCtrl;
  late final TextEditingController _mqttPortCtrl;
  late final TextEditingController _deviceIdCtrl;
  late final TextEditingController _wsUrlCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.appState.settings;
    _mode = s.mode;
    _vibration = s.vibrationEnabled;
    _flash = s.flashEnabled;
    _threshold = s.confidenceThreshold;
    _mqttHostCtrl = TextEditingController(text: s.mqttHost);
    _mqttPortCtrl = TextEditingController(text: s.mqttPort.toString());
    _deviceIdCtrl = TextEditingController(text: s.deviceId);
    _wsUrlCtrl = TextEditingController(text: s.wsUrl);
  }

  @override
  void dispose() {
    _mqttHostCtrl.dispose();
    _mqttPortCtrl.dispose();
    _deviceIdCtrl.dispose();
    _wsUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final next = AppSettings(
      mode: _mode,
      mqttHost: _mqttHostCtrl.text.trim(),
      mqttPort: int.tryParse(_mqttPortCtrl.text.trim()) ?? 1883,
      deviceId: _deviceIdCtrl.text.trim().isEmpty
          ? 'BABY_MONITOR_01'
          : _deviceIdCtrl.text.trim(),
      wsUrl: _wsUrlCtrl.text.trim(),
      vibrationEnabled: _vibration,
      flashEnabled: _flash,
      confidenceThreshold: _threshold,
    );
    await widget.appState.applySettings(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장하고 기기에 다시 연결합니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle('연결 방식'),
          Container(
            decoration: cardDecoration(),
            child: RadioGroup<ConnectionMode>(
              groupValue: _mode,
              onChanged: (v) => setState(() => _mode = v!),
              child: Column(
                children: [
                  _modeTile(
                    ConnectionMode.demo,
                    Icons.play_circle_outline,
                    '데모 모드',
                    '기기 없이 앱 단독으로 체험합니다.',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _modeTile(
                    ConnectionMode.mqtt,
                    Icons.cloud_outlined,
                    '원격 확인 (MQTT)',
                    '브로커를 통해 외출 중에도 아기 상태를 확인합니다.',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _modeTile(
                    ConnectionMode.websocket,
                    Icons.wifi,
                    '같은 Wi-Fi 직접 연결',
                    '집 안에서 기기에 WebSocket으로 직접 연결합니다.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_mode == ConnectionMode.mqtt) ...[
            _sectionTitle('MQTT 브로커'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                children: [
                  _textField(_mqttHostCtrl, '브로커 주소', 'broker.hivemq.com'),
                  const SizedBox(height: 12),
                  _textField(_mqttPortCtrl, '포트', '1883',
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  _textField(_deviceIdCtrl, '기기 ID', 'BABY_MONITOR_01'),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '구독 토픽: tiramisu/babycry/${_deviceIdCtrl.text.trim()}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textGrey),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (_mode == ConnectionMode.websocket) ...[
            _sectionTitle('기기 주소'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: _textField(
                _wsUrlCtrl,
                'WebSocket 주소',
                'ws://192.168.0.10:81',
                keyboardType: TextInputType.url,
              ),
            ),
            const SizedBox(height: 20),
          ],
          _sectionTitle('알림 (청각장애 부모 접근성)'),
          Container(
            decoration: cardDecoration(),
            child: Column(
              children: [
                SwitchListTile(
                  value: _vibration,
                  activeThumbColor: AppColors.primary,
                  title: const Text('진동 알림',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('울음 감지 시 휴대폰이 진동합니다.',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() => _vibration = v),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  value: _flash,
                  activeThumbColor: AppColors.primary,
                  title: const Text('화면 색상 플래시',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('울음 감지 시 화면이 상태 색상으로 깜빡입니다.',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setState(() => _flash = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('분석 민감도'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '신뢰도 ${(_threshold * 100).toInt()}% 이상일 때만 알림·기록',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Slider(
                  value: _threshold,
                  min: 0.3,
                  max: 0.95,
                  divisions: 13,
                  activeColor: AppColors.primary,
                  label: '${(_threshold * 100).toInt()}%',
                  onChanged: (v) => setState(() => _threshold = v),
                ),
                const Text(
                  '낮게 설정하면 놓치는 울음이 줄어들지만 오탐이 늘어날 수 있어요.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textGrey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _apply,
            icon: const Icon(Icons.save_outlined),
            label: const Text('저장 후 다시 연결',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '아기 언어 번역기 v1.0 · 팀 티라미수\n본 제품은 의료기기가 아닌 육아 보조기기입니다.\n평소와 다른 지속적인 울음·발열·호흡곤란 시 의료기관 진료를 받아 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textGrey, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.bold,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _modeTile(
      ConnectionMode mode, IconData icon, String title, String subtitle) {
    return RadioListTile<ConnectionMode>(
      value: mode,
      activeColor: AppColors.primary,
      title: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textDark),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 26),
        child: Text(subtitle, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label,
      String hint,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
