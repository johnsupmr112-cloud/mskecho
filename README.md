# MSKEcho（MSK口述）— 第一階段程式

肌肉骨骼超音波報告的 iPhone 離線口述 App。開發順序見 `ROADMAP.md`。

## 一、在 Mac 上建立專案（擇一）

### 方法 A：XcodeGen（推薦，一行指令）
```bash
brew install xcodegen
cd MSKEcho          # 本資料夾（含 project.yml）
xcodegen
open MSKEcho.xcodeproj
```

### 方法 B：手動
1. Xcode › File › New › Project › iOS › **App**；Product Name `MSKEcho`、Interface **SwiftUI**、Storage **None**
2. 刪掉 Xcode 自動產生的 `ContentView.swift` 與 `MSKEchoApp.swift`
3. 把本資料夾的 `MSKEcho/` 子資料夾整個拖進 Xcode（勾選 *Copy items if needed*、*Create groups*、Target 勾 MSKEcho）
4. Target › General › Minimum Deployments 設 **iOS 17.0**
5. Target › Info 新增兩個 key：
   - `Privacy - Microphone Usage Description`：需要使用麥克風進行超音波報告口述。
   - `Privacy - Speech Recognition Usage Description`：在 iPhone 本機將口述轉為文字，音訊不會上傳。

## 二、裝到 iPhone
1. iPhone 用線接 Mac；iPhone › 設定 › 隱私權與安全性 › **開發者模式** 開啟
2. **iPhone › 設定 › 一般 › 鍵盤 › 啟用聽寫**，確認語言含「中文（台灣）」（離線模型要先下載）
3. Xcode › Target › Signing & Capabilities › Team 選你的 Apple ID / 開發者帳號
4. 上方裝置選你的 iPhone → ▶︎ Run（模擬器的語音辨識不準，請用實機）

## 三、程式結構
```
MSKEcho/
├─ App/
│  ├─ MSKEchoApp.swift        進入點 + 4 個分頁
│  └─ DictationStore.swift    串接：辨識 → 後處理 → 草稿 → 定稿 → 學習
├─ Speech/
│  ├─ SpeechEngine.swift      裝置端 zh-TW 連續辨識，停頓自動切段、不漏音
│  └─ CustomLMTrainer.swift   iPhone 本機訓練自訂語言模型
├─ Learning/
│  ├─ Tokenizer.swift         中英夾雜斷詞
│  ├─ PostProcessor.swift     誤辨修正、縮寫、大小寫、口令、中英空白
│  ├─ NumberNormalizer.swift  零點三五公分 → 0.35 cm、十二平方毫米 → 12 mm²
│  └─ CorrectionLearner.swift 比對你的修改 → 修正規則候選（含左右側/嚴重度保護）
├─ Models/
│  ├─ Models.swift            SwiftData：報告、學到的規則、個人詞彙
│  └─ Vocabulary.swift        讀取內建詞庫、產生偏置詞與樣板句
├─ Views/                     口述 / 報告 / 學習 / 詞庫 四個畫面
└─ Resources/msk_vocab.json   內建 MSK 詞庫（260 詞、33 縮寫、50 誤辨對照、樣板句）
```

## 四、使用流程
1. **口述**頁按麥克風 → 邊說邊出字（灰色是正在辨識的句子）
2. 說「換行」「下一段」「句號」「逗號」控制格式
3. 結束後直接在文字框修改 → 按 **定稿**：自動複製到剪貼簿、存檔、從你的修改學規則
4. **學習**頁：右滑「採用」修正候選；累積 10 份定稿自動重訓語言模型（也可手動）
5. **詞庫**頁：新增個人詞彙與「常被聽成」的錯字

## 五、同步學習資料（手機 → Mac → GitHub）

學到的東西平常只存在 iPhone 裡。定期（例如每週）做一次：

1. **iPhone**：「學習」頁 › **匯出學習資料** › AirDrop 到 Mac（檔案會在「下載項目」）
2. **Mac 終端機**（在 MSKEcho 資料夾內）：
   ```bash
   python3 scripts/merge_vocab.py ~/Downloads/MSKEcho-learning-*.json --dry-run   # 先預覽
   python3 scripts/merge_vocab.py ~/Downloads/MSKEcho-learning-<日期>.json        # 確認後合併
   ```
   會把個人詞彙、已採用的規則併入 `msk_vocab.json`，並自動 git commit + push。
3. **Xcode** 按 **⌘R** → 新詞庫裝進手機。就算之後刪掉 App 也不會遺失。

換手機或重裝：「學習」頁 › **匯入學習資料**，選先前匯出的 JSON（合併，不覆蓋）。

## 六、版本管理（GitHub）

第一次設定（只做一次）：
```bash
bash scripts/setup_github.sh          # 建立私人 repo「mskecho」並上傳
```
之後新增或刪除 Swift 檔案時：
```bash
bash scripts/regen.sh                 # 重新產生 Xcode 專案（保留你的 Team 與 Bundle ID）
```
修改程式後一鍵上傳：`bash scripts/push.sh "這次改了什麼"`（或用 Xcode › Integrate › Commit，勾 Push）

> `MSKEcho.xcodeproj` 不進版本庫（由 project.yml 產生）；從 iPhone 匯出的原始 JSON 也不會被上傳。

## 七、已知限制 / 下一步
- 自訂語言模型若 iOS 不支援 zh-TW 會顯示「訓練失敗」，此時仍有詞彙偏置 + 修正規則兩層在運作 → Phase 4 改評估 WhisperKit
- 尚未存音檔（Phase 4 的測試集與 Phase 5 微調才需要）
- 尚無結構化範本（Phase 3）
