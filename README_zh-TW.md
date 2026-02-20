<p align="center">
  <img src="assets/logo.png" width="128" alt="opview">
</p>

# opview

[English](README.md) | **繁體中文**

複製 [openpilot](https://github.com/commaai/openpilot) 原廠行車介面，以 Flutter 建構，支援 iOS 與 Android。
不需要 3D 函式庫，所有投影皆為純 Dart 3x3 矩陣運算。

## 使用方式

1. 將手機連接到與 comma 裝置**相同的 WiFi 網路**
2. 安裝並開啟 opview
3. 當裝置進入行車狀態後，即可看到即時道路畫面與完整的 openpilot HUD 覆蓋

**需求：**
- 已啟用 webrtcd 的 [openpilot](https://github.com/commaai/openpilot)（見下方說明），或 [dragonpilot](https://github.com/dragonpilot-community/dragonpilot) 0.10.3+
- 手機與 comma 裝置在同一個區域網路
- comma 裝置的 `webrtcd` 服務需可透過 port 5001 存取（原廠 openpilot 預設值）

**在原廠 openpilot 啟用 webrtcd：**

在 `selfdrive/manager/process_config.py` 中找到 `webrtcd` 和 `stream_encoderd`，將條件從 `notcar` 改為 `or_(notcar, only_onroad)`：
```python
PythonProcess("webrtcd", "system.webrtc.webrtcd", or_(notcar, only_onroad)),
NativeProcess("stream_encoderd", "system/loggerd", ["./encoderd", "--stream"], or_(notcar, only_onroad)),
```

## 架構

```
├── assets/
│   └── logo.png                           # 來源圖示（產生所有 app icon）
├── scripts/
│   ├── build.sh                           # 建置腳本（Android/iOS）
│   └── generate_icons.py                  # 從 logo.png 產生圖示
├── lib/
│   ├── main.dart                          # 進入點、橫向鎖定、沉浸模式
│   ├── app.dart                           # MaterialApp 外殼、生命週期（暫停/恢復）
│   ├── common/
│   │   └── transformations.dart           # DEVICE_CAMERAS、rotFromEuler、matmul3x3
│   ├── selfdrive/ui/
│   │   ├── ui_state.dart                  # UIState ChangeNotifier，資料驅動更新
│   │   └── onroad/
│   │       ├── augmented_road_view.dart   # 主畫面、圖層堆疊、邊框、校準
│   │       ├── model_renderer.dart        # 路徑、車道線、道路邊緣、前車指示
│   │       ├── hud_renderer.dart          # 速度顯示、MAX 巡航框、頂部漸層
│   │       └── alert_renderer.dart        # 依嚴重程度著色的警示橫幅
│   ├── system/webrtc/
│   │   ├── webrtc_client.dart             # PeerConnection、H264 SDP 偏好
│   │   └── webrtcd_api.dart               # POST /stream SDP 交換
│   ├── services/
│   │   ├── discovery.dart                 # 抽象裝置探索介面
│   │   ├── transport.dart                 # 抽象傳輸介面
│   │   ├── adapter.dart                   # 抽象遙測轉接介面
│   │   ├── connection_manager.dart        # 探索 → 傳輸 → 轉接 → UIState
│   │   ├── wake_lock_service.dart         # 螢幕常亮切換（platform channel）
│   │   └── impl/
│   │       ├── mdns_discovery.dart        # mDNS/NSD 自動探索（Bonjour）
│   │       ├── webrtc_transport.dart      # WebRTC 影像 + 資料通道
│   │       └── cereal_adapter.dart        # }{ 分割、NaN 清理、JSON 解碼
│   └── data/
│       └── models.dart                    # StreamRequest
└── test/
    ├── transformations_test.dart          # 矩陣運算、相機設定
    ├── telemetry_parser_test.dart         # （空殼）
    ├── ui_state_test.dart                 # 所有 apply 方法、衍生值
    ├── sdp_test.dart                      # H264 SDP 重寫
    └── models_test.dart                   # 資料模型序列化
```

## 建置

需要 Flutter 3.x。

```bash
# 快速建置
scripts/build.sh           # Android（預設）
scripts/build.sh ios       # iOS（需要 macOS + Xcode）

# 或手動
flutter build apk --release
flutter build ios --release
```

## 平台說明

- **Android 手機/平板** — 直接可用
- **Android 車機** — 可用，`minSdk 21` 涵蓋大多數副廠主機
- **iOS** — 尚未測試建置，Bonjour 權限已在 Info.plist 中預先設定
- **Android Auto / Apple CarPlay** — 不支援。兩個平台皆限制 app 為導航、媒體、訊息或電動車充電類別，並強制使用範本式 UI，無法自訂繪製畫面

## 分支

| 分支 | 說明 |
|------|------|
| `main` | 穩定版本 |
| `perf-optimizations` | 實驗性效能改進 |

### perf-optimizations

針對低階裝置降低 CPU/GPU 使用率的效能調校：

- **簡化車道線** — 使用描邊線條取代填充多邊形
- **簡化道路邊緣** — 使用描邊線條取代填充多邊形
- **簡化實驗模式漸層** — 5 個取樣點取代逐點漸層

透過 `model_renderer.dart` 中的常數切換：
```dart
const useSimpleLaneLines = true;
const useSimpleRoadEdges = true;
const useSimpleExpGradient = true;
```

## 移植來源

| 來源 | 內容 |
|------|------|
| `openpilot/selfdrive/ui/` | UIState、augmented_road_view、model_renderer、hud_renderer、alert_renderer |
| `openpilot/common/transformations/` | 相機內參、rotFromEuler、view_frame_from_device_frame |
| `openpilot/system/webrtc/webrtcd.py` | POST /stream API、資料通道格式 |
| `dashy` | 影像縮放感知校準、H264 SDP 重寫、NaN 處理、}{ 分割、NSD 探索 |

## 授權條款

請參閱 [LICENSE](LICENSE)。
