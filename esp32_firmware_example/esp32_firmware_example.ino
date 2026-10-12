/*
 * 아기 언어 번역기 - XIAO ESP32S3 Sense 예제 펌웨어 (팀 티라미수)
 *
 * 역할: 내장 PDM 마이크로 소리를 수집하고, 울음 분류 결과를
 *       MQTT 브로커에 발행(publish)하여 앱이 원격으로 확인할 수 있게 한다.
 *
 * 앱 연동 규격:
 *   토픽   : tiramisu/babycry/{DEVICE_ID}
 *   페이로드: {"device_id":"BABY_MONITOR_01","timestamp":"...","detected_sound":"Neh",
 *             "confidence_score":0.92,"decibel_level":65}
 *
 * 필요 라이브러리 (Arduino IDE 라이브러리 매니저에서 설치):
 *   - PubSubClient (Nick O'Leary)
 *   - ArduinoJson (Benoit Blanchon)
 *   - arduinoFFT (kosme) — 주파수 분석용
 *
 * 보드 설정: Tools > Board > "XIAO_ESP32S3", PSRAM: "OPI PSRAM"
 *
 * 분류 방식 (프로토타입 휴리스틱):
 *   큰 소리가 감지되면 2초간 소리의 특징을 수집한 뒤 던스턴 5분류에 매핑한다.
 *   - 평균 주파수 (FFT 주요 피크)
 *   - 지속 비율 (2초 중 큰 소리가 차지한 비율)
 *   - 버스트 횟수 (소리가 끊겼다 다시 나는 반복 리듬)
 *   실제 제품 수준의 정확도를 위해서는 이 함수를 학습 모델(Edge Impulse 등)
 *   추론으로 교체해야 한다. 구조는 그대로 재사용 가능.
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <ESP_I2S.h>   // XIAO ESP32S3 Sense 내장 PDM 마이크 (ESP32 코어 3.x)
#include <arduinoFFT.h>
#include <time.h>
#include <Preferences.h>

// ===== 사용자 설정 =====
const char* WIFI_SSID     = "WMS";
const char* WIFI_PASSWORD = "WMS1348B2F";
const char* MQTT_HOST     = "broker.hivemq.com";   // 앱 설정과 동일해야 함
const int   MQTT_PORT     = 1883;
const char* DEVICE_ID     = "BABY_MONITOR_01";     // 앱 설정과 동일해야 함

// ===== 마이크 설정 =====
const int SAMPLE_RATE = 16000;
const int SAMPLE_BUFFER_SIZE = 512;

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
Preferences wifiPrefs;
I2SClass i2s;

char mqttTopic[64];
int16_t sampleBuffer[SAMPLE_BUFFER_SIZE];

void onMqttMessage(char* topic, byte* payload, unsigned int length);

// FFT 주파수 분석 버퍼
double fftReal[SAMPLE_BUFFER_SIZE];
double fftImag[SAMPLE_BUFFER_SIZE];
ArduinoFFT<double> FFT(fftReal, fftImag, SAMPLE_BUFFER_SIZE, (double)SAMPLE_RATE);

// 에피소드 분석 중 기록되는 최대 음량 (publish 시 사용)
int episodeMaxDb = 0;

void setup() {
  Serial.begin(115200);

  snprintf(mqttTopic, sizeof(mqttTopic), "tiramisu/babycry/%s", DEVICE_ID);

  connectWiFi();

  // 타임스탬프용 NTP 시간 동기화 (UTC)
  configTime(0, 0, "pool.ntp.org");

  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(512);
  mqtt.setSocketTimeout(3);  // 연결 시도가 오래 걸려도 3초 안에 포기 (감지 중단 최소화)
  mqtt.setCallback(onMqttMessage);

  // XIAO ESP32S3 Sense 내장 PDM 마이크: CLK=GPIO42, DATA=GPIO41
  i2s.setPinsPdmRx(42, 41);
  if (!i2s.begin(I2S_MODE_PDM_RX, SAMPLE_RATE, I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO)) {
    Serial.println("마이크 초기화 실패!");
    while (true) delay(1000);
  }
  Serial.println("아기 울음 감지 시작");
}

void loop() {
  // 연결이 끊겨도 소리 감지는 멈추지 않는다 (백그라운드 재연결)
  ensureConnections();
  mqtt.loop();

  // 1) 마이크 샘플 수집
  size_t bytesRead = i2s.readBytes((char*)sampleBuffer, sizeof(sampleBuffer));
  int samples = bytesRead / sizeof(int16_t);
  if (samples == 0) return;

  // 2) 음량(dB 근사) 계산
  int decibel = estimateDecibel(sampleBuffer, samples);

  // 캘리브레이션용: 2초마다 최근 최대 dB를 시리얼로 출력
  static int peakDb = 0;
  static unsigned long lastDebug = 0;
  if (decibel > peakDb) peakDb = decibel;
  if (millis() - lastDebug > 2000) {
    Serial.printf("[dB] 최근 2초 피크: %d\n", peakDb);
    peakDb = 0;
    lastDebug = millis();
  }

  // 3) 울음 분류
  //    ★ 여기에 팀의 주파수/음역대/호흡 길이 기반 분류 알고리즘을 연결하세요.
  //    (Edge Impulse 등으로 학습한 모델의 추론 결과를 넣는 위치)
  float confidence = 0.0;
  const char* sound = classifyCry(sampleBuffer, samples, decibel, &confidence);

  // 4) 울음으로 판단되면 앱으로 전송 (연속 전송 방지: 5초 간격)
  static unsigned long lastPublish = 0;
  if (sound != nullptr && millis() - lastPublish > 5000) {
    publishCryEvent(sound, confidence, episodeMaxDb);
    lastPublish = millis();
  }
}

// 샘플 진폭으로 dB SPL을 근사한다 (마이크 감도 보정 전 상대값).
int estimateDecibel(const int16_t* buf, int n) {
  double sumSq = 0;
  for (int i = 0; i < n; i++) sumSq += (double)buf[i] * buf[i];
  double rms = sqrt(sumSq / n);
  if (rms < 1) rms = 1;
  // 16bit full scale 기준 dBFS를 대략적인 dB SPL 범위(+94 오프셋 근사)로 변환
  int db = (int)(20.0 * log10(rms / 32768.0) + 94.0);
  return constrain(db, 30, 110);
}

// 현재 윈도우의 주요 주파수(Hz)를 FFT로 추출한다.
float dominantFreq(const int16_t* buf, int n) {
  for (int i = 0; i < n; i++) {
    fftReal[i] = (double)buf[i];
    fftImag[i] = 0.0;
  }
  FFT.windowing(FFTWindow::Hamming, FFTDirection::Forward);
  FFT.compute(FFTDirection::Forward);
  FFT.complexToMagnitude();
  return (float)FFT.majorPeak();
}

// 던스턴 5분류 휴리스틱 (프로토타입).
//
// 동작: [대기] 큰 소리(68dB+)가 1초 창에서 2윈도우 이상 → [수집] 2초간 특징 기록
//       → 평균 주파수·지속 비율·버스트 리듬으로 분류 → 태그 반환.
// 실제 정확도를 위해서는 이 판정부를 학습 모델 추론으로 교체할 것.
const char* classifyCry(const int16_t* buf, int n, int decibel, float* confidence) {
  const int LOUD_DB = 68;          // 큰 소리 기준 (실내 소음 ~66dB보다 살짝 높게)
  const int TRIGGER_WINDOWS = 2;   // 1초 창에서 이 개수 이상이면 울음 후보
  const int EPISODE_WINDOWS = 60;  // 특징 수집 길이: 32ms × 60 ≈ 2초

  static bool recording = false;
  // 대기 상태용 (울음 후보 감시)
  static int watchWin = 0, watchLoud = 0;
  static float watchPitchSum = 0;
  static int watchMaxDb = 0;
  // 수집 상태용 (특징 누적)
  static int epWin = 0, epLoud = 0, epBursts = 0;
  static bool prevLoud = false;
  static float pitchSum = 0;
  static int pitchN = 0;

  bool loud = decibel >= LOUD_DB;

  if (!recording) {
    watchWin++;
    if (loud) {
      watchLoud++;
      // 트리거를 일으킨 소리 자체도 분류 통계에 포함시킨다
      // (짧은 소리가 수집 단계에서 꼬리만 남아 오탐 처리되는 것 방지)
      float p = dominantFreq(buf, n);
      if (p > 100 && p < 3000) watchPitchSum += p;
      if (decibel > watchMaxDb) watchMaxDb = decibel;
    }
    if (watchLoud >= TRIGGER_WINDOWS) {
      recording = true;
      // 대기 단계에서 수집한 소리 특징을 시드로 사용
      epWin = 0; epLoud = watchLoud; epBursts = 1; prevLoud = true;
      pitchSum = watchPitchSum; pitchN = watchLoud;
      episodeMaxDb = watchMaxDb;
      watchWin = 0; watchLoud = 0; watchPitchSum = 0; watchMaxDb = 0;
      Serial.println("[분석] 울음 후보 감지 → 2초간 특징 수집 중...");
    } else if (watchWin >= 30) {
      watchWin = 0; watchLoud = 0; watchPitchSum = 0; watchMaxDb = 0;
    }
    return nullptr;
  }

  // ===== 특징 수집 중 =====
  epWin++;
  if (loud) {
    epLoud++;
    if (!prevLoud) epBursts++;  // 조용→큼 전환 = 새 버스트
    if (decibel > episodeMaxDb) episodeMaxDb = decibel;
    float p = dominantFreq(buf, n);
    if (p > 100 && p < 3000) {  // 사람 소리 대역만 집계
      pitchSum += p;
      pitchN++;
    }
  }
  prevLoud = loud;
  if (epWin < EPISODE_WINDOWS) return nullptr;

  // ===== 수집 완료 → 분류 =====
  recording = false;
  float avgPitch = pitchN > 0 ? pitchSum / pitchN : 0;
  float loudRatio = (float)epLoud / EPISODE_WINDOWS;

  Serial.printf("[분석] 평균 주파수 %.0fHz, 지속 비율 %.0f%%, 버스트 %d회, 최대 %ddB\n",
                avgPitch, loudRatio * 100, epBursts, episodeMaxDb);

  if (epLoud < TRIGGER_WINDOWS) return nullptr;  // 수집 중 소리가 사라짐 → 오탐

  // 던스턴 휴리스틱 매핑 (수집한 특징 → 5분류)
  const char* tag;
  if (avgPitch > 0 && avgPitch < 350) {
    tag = "Owh";  *confidence = 0.75;  // 낮고 둥근 하품형 소리 → 졸림
  } else if (loudRatio > 0.5 && avgPitch >= 500) {
    tag = "Eair"; *confidence = 0.78;  // 길게 쥐어짜는 억센 소리 → 하복부 가스
  } else if (epBursts >= 4) {
    tag = "Neh";  *confidence = 0.80;  // 반복 리듬 (네-네-네) → 배고픔
  } else if (loudRatio < 0.2) {
    tag = "Eh";   *confidence = 0.70;  // 짧게 뚝뚝 끊기는 소리 → 트림 필요
  } else {
    tag = "Heh";  *confidence = 0.72;  // 중간 높이의 가쁜 소리 → 불편함
  }
  Serial.printf("[분류] %s (신뢰도 %.0f%%)\n", tag, *confidence * 100);
  return tag;
}

void publishCryEvent(const char* sound, float confidence, int decibel) {
  char timestamp[32];
  time_t now = time(nullptr);
  strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));

  JsonDocument doc;
  doc["device_id"] = DEVICE_ID;
  doc["timestamp"] = timestamp;
  doc["detected_sound"] = sound;
  doc["confidence_score"] = confidence;
  doc["decibel_level"] = decibel;

  char payload[256];
  serializeJson(doc, payload, sizeof(payload));

  if (mqtt.connected()) {
    mqtt.publish(mqttTopic, payload);
    Serial.printf("전송: %s\n", payload);
  } else {
    Serial.printf("전송 보류 (브로커 연결 없음): %s\n", payload);
  }
}

void connectWiFi() {
  wifiPrefs.begin("wifi", true);
  String storedSsid = wifiPrefs.getString("ssid", WIFI_SSID);
  String storedPassword = wifiPrefs.getString("password", WIFI_PASSWORD);
  wifiPrefs.end();
  Serial.printf("Wi-Fi 연결 중: %s\n", storedSsid.c_str());
  WiFi.begin(storedSsid.c_str(), storedPassword.c_str());
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\n연결 완료. IP: %s\n", WiFi.localIP().toString().c_str());
}

// Wi-Fi/MQTT 상태를 점검하고 끊겨 있으면 재연결을 시도한다.
// 블로킹 루프 없이 5~10초 간격으로만 시도하므로 소리 감지가 중단되지 않는다.
void ensureConnections() {
  static unsigned long lastAttempt = 0;

  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - lastAttempt > 10000) {
      lastAttempt = millis();
      Serial.println("Wi-Fi 끊김 → 재연결 시도...");
      WiFi.disconnect();
      wifiPrefs.begin("wifi", true);
      String storedSsid = wifiPrefs.getString("ssid", WIFI_SSID);
      String storedPassword = wifiPrefs.getString("password", WIFI_PASSWORD);
      wifiPrefs.end();
      WiFi.begin(storedSsid.c_str(), storedPassword.c_str());
    }
    return; // Wi-Fi가 없으면 MQTT 시도는 무의미
  }

  if (!mqtt.connected() && millis() - lastAttempt > 5000) {
    lastAttempt = millis();
    char clientId[48];
    snprintf(clientId, sizeof(clientId), "tiramisu_dev_%s_%lu", DEVICE_ID, millis());
    if (mqtt.connect(clientId)) {
      char configTopic[96];
      snprintf(configTopic, sizeof(configTopic), "tiramisu/babycry/%s/config", DEVICE_ID);
      mqtt.subscribe(configTopic);
      Serial.println("MQTT 브로커 연결 완료");
    } else {
      Serial.printf("MQTT 연결 실패 (rc=%d), 5초 후 재시도\n", mqtt.state());
    }
  }
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  StaticJsonDocument<256> doc;
  if (deserializeJson(doc, payload, length)) return;
  const char* ssid = doc["ssid"] | "";
  const char* password = doc["password"] | "";
  if (!ssid[0] || !password[0]) return;
  wifiPrefs.begin("wifi", false);
  wifiPrefs.putString("ssid", ssid);
  wifiPrefs.putString("password", password);
  wifiPrefs.end();
  Serial.printf("새 Wi-Fi 설정 저장: %s\n", ssid);
  WiFi.disconnect(true);
  delay(300);
  WiFi.begin(ssid, password);
}
