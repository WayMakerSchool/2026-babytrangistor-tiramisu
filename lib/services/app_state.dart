import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../models/baby_cry_data.dart';
import 'app_settings.dart';
import 'connection_service.dart';
import 'cry_translator.dart';

/// 앱 전역 상태: 설정, 하드웨어 연결, 최신 울음 데이터, 기록, 접근성 알림.
class AppState extends ChangeNotifier {
  static const _historyKey = 'cry_history';
  static const _maxHistory = 200;

  AppSettings settings;
  ConnectionService _service;
  StreamSubscription? _dataSub;
  StreamSubscription? _statusSub;

  BabyCryData? current;
  final List<BabyCryData> history = [];

  /// 화면 플래시 알림용: 새 울음 이벤트마다 증가한다.
  int alertTick = 0;

  AppState._(this.settings) : _service = ConnectionService.forSettings(settings);

  static Future<AppState> create() async {
    final settings = await AppSettings.load();
    final state = AppState._(settings);
    await state._loadHistory();
    state._bind();
    unawaited(state._service.connect());
    return state;
  }

  ConnectionStatus get connectionStatus => _service.status;
  bool get isDemo => settings.mode == ConnectionMode.demo;
  DemoConnectionService? get demoService =>
      _service is DemoConnectionService ? _service as DemoConnectionService : null;

  TranslationResult get currentTranslation =>
      CryTranslator.translate(current?.detectedSound ?? 'Unknown');

  void _bind() {
    _dataSub = _service.dataStream.listen(_onData);
    _statusSub = _service.statusStream.listen((_) => notifyListeners());
  }

  void _onData(BabyCryData data) {
    current = data;
    final result = CryTranslator.translate(data.detectedSound);
    final meaningful =
        result.isCry && data.confidenceScore >= settings.confidenceThreshold;

    if (meaningful) {
      history.insert(0, data);
      if (history.length > _maxHistory) {
        history.removeRange(_maxHistory, history.length);
      }
      unawaited(_saveHistory());
      unawaited(_notifyAccessibility());
      alertTick++;
    }
    notifyListeners();
  }

  /// 청각장애 부모 접근성: 진동 패턴 알림.
  /// 화면 플래시는 alertTick을 구독하는 UI에서 처리한다.
  Future<void> _notifyAccessibility() async {
    if (!settings.vibrationEnabled) return;
    try {
      if (await Vibration.hasVibrator()) {
        // 두 번 길게 울리는 패턴: 손목/주머니에서도 인지 가능
        await Vibration.vibrate(pattern: [0, 400, 200, 400]);
      }
    } catch (_) {
      // 진동 미지원 기기(일부 태블릿 등)는 조용히 넘어간다.
    }
  }

  /// 연결 방식/주소 변경 후 재연결.
  Future<void> applySettings(AppSettings next) async {
    settings = next;
    await settings.save();
    await _dataSub?.cancel();
    await _statusSub?.cancel();
    await _service.disconnect();
    _service.dispose();
    _service = ConnectionService.forSettings(settings);
    _bind();
    notifyListeners();
    await _service.connect();
  }

  Future<void> reconnect() async {
    await _service.disconnect();
    await _service.connect();
  }

  Future<void> clearHistory() async {
    history.clear();
    await _saveHistory();
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey) ?? [];
    history
      ..clear()
      ..addAll(raw.map((e) {
        try {
          return BabyCryData.fromJson(jsonDecode(e) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<BabyCryData>());
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _historyKey,
      history.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _statusSub?.cancel();
    _service.disconnect();
    _service.dispose();
    super.dispose();
  }
}
