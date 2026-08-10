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
 *   - U8g2 (olikraus) — OLED 표시 (한글 폰트 내장)
 *
 * 보드 설정: Tools > Board > "XIAO_ESP32S3", PSRAM: "OPI PSRAM"
 *
 * OLED 배선 (SSD1306 128x64, I2C):
 *   VCC→3V3, GND→GND, SDA→D5(GPIO6), SCL→D4(GPIO5)
 *   ※ 이 보드의 실제 배선 기준(SDA/SCL이 기본과 반대). 코드도 이 핀으로 맞춤(SW I2C).
 *
 * OLED 표시 규칙:
 *   - 조용할 때        : QUIET
 *   - 울음 감지·분석 중 : CRYING
 *   - 번역(분류) 완료  : 던스턴 결과를 한글로 (배고픔/졸림/트림 등), 잠시 후 QUIET 복귀
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
#include <Wire.h>
#include <U8g2lib.h>   // OLED 표시 (한글 폰트 렌더링 지원)
#include <time.h>

// ===== 사용자 설정 =====
const char* WIFI_SSID     = "WMS";
const char* WIFI_PASSWORD = "WMS1348B2F";
const char* MQTT_HOST     = "broker.hivemq.com";   // 앱 설정과 동일해야 함
const int   MQTT_PORT     = 1883;
const char* DEVICE_ID     = "BABY_MONITOR_01";     // 앱 설정과 동일해야 함

// ===== 마이크 설정 =====
const int SAMPLE_RATE = 16000;
const int SAMPLE_BUFFER_SIZE = 512;

// ===== OLED 설정 (SSD1306 128x64, I2C) =====
const int OLED_ADDR = 0x3C;   // 대부분의 128x64 모듈 기본 주소 (0x3D인 경우도 있음)
// 실제 배선: SDA→D5(GPIO6), SCL→D4(GPIO5) — 기본과 반대라 핀을 명시한다.
const int OLED_SDA = 6;   // D5
const int OLED_SCL = 5;   // D4

// 한글 폰트: 특정 글자가 안 나오면 korean2 → korean1 로 바꿔볼 것
// (U8g2 한글 폰트는 자주 쓰는 글자를 두 세트로 나눠 담고 있음)
#define OLED_KO_FONT u8g2_font_unifont_t_korean2

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
I2SClass i2s;
// 소프트웨어 I2C로 핀을 정확히 지정 (HW I2C는 Wire 재초기화로 커스텀 핀이 무시될 수 있음)
U8G2_SSD1306_128X64_NONAME_F_SW_I2C oled(U8G2_R0, OLED_SCL, OLED_SDA, U8X8_PIN_NONE);
bool oledReady = false;   // OLED 검출 성공 여부 (실패해도 감지는 계속)

char mqttTopic[64];
int16_t sampleBuffer[SAMPLE_BUFFER_SIZE];

// ===== 화면 상태 머신 =====
//   QUIET  : 조용함 (대기)
//   CRYING : 울음 감지 → 특징 수집(분석) 중
//   RESULT : 던스턴 분류 완료 → 한글 의미 표시
enum CryState { STATE_QUIET, STATE_CRYING, STATE_RESULT };
CryState cryState = STATE_QUIET;
unsigned long resultShownAt = 0;                 // RESULT 진입 시각
const unsigned long RESULT_HOLD_MS = 10000;      // 결과 표시 유지 시간(이후 QUIET 복귀)

// 화면에 표시할 마지막 울음 정보
char  lastSound[8] = "";   // 로마자 태그 (예: "Neh")
float lastConf     = 0.0;  // 신뢰도
int   lastLiveDb   = 0;    // 실시간 dB (헤더용)

// FFT 주파수 분석 버퍼
double fftReal[SAMPLE_BUFFER_SIZE];
double fftImag[SAMPLE_BUFFER_SIZE];
ArduinoFFT<double> FFT(fftReal, fftImag, SAMPLE_BUFFER_SIZE, (double)SAMPLE_RATE);

// 에피소드 분석 중 기록되는 최대 음량 (publish 시 사용)
int episodeMaxDb = 0;

// ===== 적응형 감지 기준 =====
// 주변 소음(배경)을 실시간으로 추적해서, 그보다 LOUD_MARGIN(dB) 위를 넘을 때만
// '큰 소리'로 본다. 방이 시끄럽든 조용하든 자동으로 기준이 맞춰져 감지가 일관적이 된다.
float noiseFloor = 58.0;              // 적응형 배경 소음(자동 보정, 초기 추정값)
const float LOUD_MARGIN = 4.0;       // 배경보다 이만큼 커야 울음 후보 (작을수록 민감, 너무 작으면 오탐↑)
const int   LOUD_FLOOR_MIN = 66;     // 배경이 아주 조용해도 이 값 밑으로는 안 내려감(생활소음 오탐 방지)
int loudThreshold = 72;              // 최종 감지 기준(= max(noiseFloor+margin, floor_min)), loop에서 갱신

// 배경 소음 추정치를 갱신한다: 조용해지면 빠르게 따라 내려가고,
// 배경 수준일 때만 완만히 올라간다.
// ★ 울음 분석 중(STATE_CRYING)에는 상승을 멈춘다 — 그렇지 않으면 울음소리 자체가
//   배경값을 끌어올려, 감지할 때마다 점점 둔감해지는 문제가 생긴다.
void updateNoiseFloor(int decibel) {
  if (decibel < noiseFloor) {
    noiseFloor += 0.30f * (decibel - noiseFloor);       // 하강: 빠르게 (조용해지면 즉시 따라감)
  } else if (cryState != STATE_CRYING) {
    noiseFloor += 0.02f * (decibel - noiseFloor);       // 상승: 분석 중이 아닐 때만 완만히
  }
  if (noiseFloor < 40) noiseFloor = 40;
}

void setup() {
  Serial.begin(115200);

  snprintf(mqttTopic, sizeof(mqttTopic), "tiramisu/babycry/%s", DEVICE_ID);

  // OLED 초기화 (XIAO ESP32S3 기본 I2C: SDA=D4/GPIO5, SCL=D5/GPIO6)
  // I2C로 모듈 존재 여부를 먼저 확인 → 없으면 화면 없이 감지만 진행
  Wire.begin(OLED_SDA, OLED_SCL);
  Wire.beginTransmission(OLED_ADDR);
  oledReady = (Wire.endTransmission() == 0);
  Wire.end();               // HW I2C 해제 (표시는 SW I2C가 담당)
  if (oledReady) {
    oled.begin();
    oled.enableUTF8Print();
    showBootScreen();
  } else {
    Serial.println("OLED 미검출 (배선/주소 확인) — 화면 없이 계속 진행");
  }

  connectWiFi();

  // 타임스탬프용 NTP 시간 동기화 (UTC)
  configTime(0, 0, "pool.ntp.org");

  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(512);
  mqtt.setSocketTimeout(3);  // 연결 시도가 오래 걸려도 3초 안에 포기 (감지 중단 최소화)

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

  // 2-1) 적응형 감지 기준 갱신: 배경 소음을 추적해 동적 임계값을 만든다
  updateNoiseFloor(decibel);
  loudThreshold = (int)noiseFloor + (int)LOUD_MARGIN;
  if (loudThreshold < LOUD_FLOOR_MIN) loudThreshold = LOUD_FLOOR_MIN;

  // 캘리브레이션용: 2초마다 피크/배경/기준을 시리얼로 출력
  static int peakDb = 0;
  static unsigned long lastDebug = 0;
  if (decibel > peakDb) peakDb = decibel;
  if (millis() - lastDebug > 2000) {
    Serial.printf("[dB] 피크:%d  배경:%.0f  감지기준:%d\n", peakDb, noiseFloor, loudThreshold);
    peakDb = 0;
    lastDebug = millis();
  }

  // 결과 표시 시간이 지나면 다시 QUIET로 복귀
  if (cryState == STATE_RESULT && millis() - resultShownAt > RESULT_HOLD_MS) {
    cryState = STATE_QUIET;
  }

  // OLED 갱신: 실시간 dB/연결 상태를 500ms마다 표시 (I2C 부하 최소화)
  static unsigned long lastOled = 0;
  if (decibel > lastLiveDb) lastLiveDb = decibel;
  if (millis() - lastOled > 500) {
    updateDisplay();
    lastLiveDb = 0;
    lastOled = millis();
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

    // 번역(분류) 완료 → 결과 화면으로 전환 후 즉시 갱신
    strncpy(lastSound, sound, sizeof(lastSound) - 1);
    lastSound[sizeof(lastSound) - 1] = '\0';
    lastConf = confidence;
    cryState = STATE_RESULT;
    resultShownAt = millis();
    updateDisplay();
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

// 현재 윈도우의 '소리 밝기'(스펙트럴 센트로이드, Hz)를 FFT로 계산한다.
//
// 단순 최대피크(기본 주파수)는 모음이 달라도 목소리 높이(~130Hz)로 비슷하게 나와서
// "이"와 "아"를 구분하지 못한다. 반면 스펙트럴 센트로이드는 스펙트럼의 무게중심이라,
// 고주파 포먼트가 많은 "이" 같은 밝은 소리에서 확실히 높게 나온다.
float dominantFreq(const int16_t* buf, int n) {
  for (int i = 0; i < n; i++) {
    fftReal[i] = (double)buf[i];
    fftImag[i] = 0.0;
  }
  FFT.windowing(FFTWindow::Hamming, FFTDirection::Forward);
  FFT.compute(FFTDirection::Forward);
  FFT.complexToMagnitude();  // 이후 fftReal[i] = i번째 주파수 빈의 크기(magnitude)

  double num = 0, den = 0;
  int half = n / 2;
  for (int i = 1; i < half; i++) {
    double freq = (double)i * SAMPLE_RATE / n;   // 이 빈의 실제 주파수(Hz)
    if (freq < 150 || freq > 4000) continue;      // 사람 소리 대역만 집계
    num += freq * fftReal[i];
    den += fftReal[i];
  }
  return den > 0 ? (float)(num / den) : 0;
}

// 던스턴 5분류 휴리스틱 (프로토타입).
//
// 동작: [대기] 큰 소리(68dB+)가 1초 창에서 2윈도우 이상 → [수집] 2초간 특징 기록
//       → 평균 주파수·지속 비율·버스트 리듬으로 분류 → 태그 반환.
// 실제 정확도를 위해서는 이 판정부를 학습 모델 추론으로 교체할 것.
const char* classifyCry(const int16_t* buf, int n, int decibel, float* confidence) {
  const int LOUD_DB = loudThreshold;  // 적응형 기준(배경 소음 + 여유폭). loop에서 매 순간 갱신
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
      if (p > 200 && p < 4000) watchPitchSum += p;
      if (decibel > watchMaxDb) watchMaxDb = decibel;
    }
    if (watchLoud >= TRIGGER_WINDOWS) {
      recording = true;
      cryState = STATE_CRYING;   // 울음 감지 → 화면에 CRYING (분석하는 동안만)
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
    if (p > 200 && p < 4000) {  // 사람 소리 대역만 집계
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

  if (epLoud < TRIGGER_WINDOWS) {  // 수집 중 소리가 사라짐 → 오탐
    cryState = STATE_QUIET;        // 울음 아님 → 다시 QUIET
    return nullptr;
  }

  // 던스턴 휴리스틱 매핑 (수집한 특징 → 5분류)
  //
  // 소리에 따라 서로 다른 결과가 나오도록, 변별력이 큰 특징부터 순서대로 판정한다.
  //   epBursts   : 끊겼다 다시 나는 반복 리듬 횟수 (많을수록 "네-네-네" 형)
  //   loudRatio  : 2초 중 큰 소리가 이어진 비율 (높을수록 길게 지속)
  //   avgPitch   : 평균 주파수 (높을수록 날카로운 톤)
  // ※ 특정 태그로 쏠리지 않게 임계값을 관측 데이터 기준으로 벌려 둠.
  // 이 마이크로 '확실히 구분되는' 특징(소리 크기·리듬·지속시간)만 사용한다.
  // (모음 "이"/"아" 구분은 단순 주파수 분석으론 불가 → 학습 모델 필요 영역)
  const char* tag;
  if (episodeMaxDb >= 78) {
    tag = "Heh";  *confidence = 0.76;  // 크고 날카로운 비명 → 통증
  } else if (epBursts >= 6) {
    tag = "Neh";  *confidence = 0.80;  // 반복 리듬 강함 (네-네-네) → 배고픔
  } else if (loudRatio >= 0.55) {
    tag = "Eair"; *confidence = 0.78;  // 길게 이어지는 억센 소리 → 배 아픔
  } else if (loudRatio < 0.25) {
    tag = "Eh";   *confidence = 0.72;  // 짧게 뚝뚝 끊기는 소리 → 트림
  } else {
    tag = "Owh";  *confidence = 0.75;  // 낮고 완만하게 이어지는 소리 → 졸림
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

// 로마자 태그를 던스턴 베이비 랭귀지 한글 의미로 변환.
const char* soundMeaningKo(const char* tag) {
  if (strcmp(tag, "Neh") == 0)  return "배고픔";
  if (strcmp(tag, "Owh") == 0)  return "졸림";
  if (strcmp(tag, "Eair") == 0) return "배 아픔";
  if (strcmp(tag, "Eh") == 0)   return "트림";
  if (strcmp(tag, "Heh") == 0)  return "통증";
  return "-";
}

// 현재 폰트 기준으로 문자열을 가로 중앙에 그린다 (ASCII).
void drawCenteredStr(const char* s, int y) {
  int w = oled.getStrWidth(s);
  oled.drawStr((128 - w) / 2, y, s);
}

// 현재 폰트 기준으로 UTF-8(한글) 문자열을 가로 중앙에 그린다.
void drawCenteredUTF8(const char* s, int y) {
  int w = oled.getUTF8Width(s);
  oled.drawUTF8((128 - w) / 2, y, s);
}

// 부팅 시 안내 화면.
void showBootScreen() {
  if (!oledReady) return;
  oled.clearBuffer();
  oled.setFont(u8g2_font_6x10_tf);
  oled.drawStr(0, 12, "Baby Cry Monitor");
  oled.drawStr(0, 26, "Team Tiramisu");
  oled.drawStr(0, 44, "Starting up...");
  oled.sendBuffer();
}

// 현재 상태(연결/실시간 dB/상태 머신)를 OLED에 그린다.
void updateDisplay() {
  if (!oledReady) return;
  oled.clearBuffer();

  // ===== 헤더: 연결 상태 + 실시간 음량 =====
  oled.setFont(u8g2_font_6x10_tf);
  char buf[32];
  bool wifiOk = WiFi.status() == WL_CONNECTED;
  bool mqttOk = mqtt.connected();
  snprintf(buf, sizeof(buf), "WiFi:%s  MQTT:%s", wifiOk ? "OK" : "--", mqttOk ? "OK" : "--");
  oled.drawStr(0, 10, buf);
  snprintf(buf, sizeof(buf), "Live: %d dB", lastLiveDb);
  oled.drawStr(0, 22, buf);
  oled.drawHLine(0, 26, 128);

  // ===== 상태 영역 =====
  if (cryState == STATE_CRYING) {
    // 울음 감지 → 분석하는 동안 CRYING
    oled.setFont(u8g2_font_helvB14_tr);
    drawCenteredStr("CRYING", 50);
    oled.setFont(u8g2_font_6x10_tf);
    drawCenteredStr("analyzing...", 62);
  } else if (cryState == STATE_RESULT) {
    // 번역 완료 → 던스턴 결과를 한글로 (배고픔/졸림 등)
    oled.setFont(OLED_KO_FONT);
    drawCenteredUTF8(soundMeaningKo(lastSound), 50);
    oled.setFont(u8g2_font_6x10_tf);
    snprintf(buf, sizeof(buf), "%s  %d%%", lastSound, (int)(lastConf * 100));
    drawCenteredStr(buf, 62);
  } else {
    // 조용함
    oled.setFont(u8g2_font_helvB14_tr);
    drawCenteredStr("QUIET", 52);
  }

  oled.sendBuffer();
}

void connectWiFi() {
  Serial.printf("Wi-Fi 연결 중: %s\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  // 최대 10초만 기다린다. 안 되면 오프라인으로 감지를 먼저 시작하고,
  // 연결은 loop()의 ensureConnections()가 백그라운드에서 계속 재시도한다.
  // (예전엔 여기서 무한 대기라, Wi-Fi가 없으면 감지·화면이 아예 안 켜졌음)
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 10000) {
    delay(300);
    Serial.print(".");
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n연결 완료. IP: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("\nWi-Fi 연결 지연 → 오프라인으로 감지 시작 (백그라운드 재시도)");
  }
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
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    }
    return; // Wi-Fi가 없으면 MQTT 시도는 무의미
  }

  if (!mqtt.connected() && millis() - lastAttempt > 5000) {
    lastAttempt = millis();
    char clientId[48];
    snprintf(clientId, sizeof(clientId), "tiramisu_dev_%s_%lu", DEVICE_ID, millis());
    if (mqtt.connect(clientId)) {
      Serial.println("MQTT 브로커 연결 완료");
    } else {
      Serial.printf("MQTT 연결 실패 (rc=%d), 5초 후 재시도\n", mqtt.state());
    }
  }
}
