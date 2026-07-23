# BLEUnlock

> [!IMPORTANT]
> 本專案是 [ts1/BLEUnlock](https://github.com/ts1/BLEUnlock) 的 fork。原始作者為 Takeshi Sone；此 fork 由 [fred-lede](https://github.com/fred-lede) 維護。
>
> 此 fork 已修改程式碼與 Xcode 專案，主要新增繁體中文介面、Telegram 通知、可選的入侵拍照與 Mac 定位資訊、Apple 裝置名稱與掃描改善、相機預熱，以及較穩定的接近確認機制。上游 Homebrew Cask 與上游 Releases 不一定包含這些功能；若要使用此 fork 的功能，請從本儲存庫原始碼編譯，除非此 fork 另有發布 Release。

本文件亦提供[英文版](README.md)與[日文版](README.ja.md)。

![CI](https://github.com/ts1/BLEUnlock/workflows/CI/badge.svg)
![Github All Releases](https://img.shields.io/github/downloads/ts1/BLEUnlock/total.svg)
[![Buy me a coffee](img/buymeacoffee.svg)](https://www.buymeacoffee.com/tsone)

## 重要說明：本應用程式未在 Mac App Store 發布，可免費取得

BLEUnlock 是一個小型選單列工具程式，會依 iPhone、Apple Watch 或其他 Bluetooth Low Energy 裝置與 Mac 的距離來鎖定及解鎖 Mac。

## 功能

- 不需要安裝 iPhone App
- 可搭配任何會定期傳送訊號且具有[固定 MAC 位址](#關於-mac-位址)的 BLE 裝置使用
- 當 BLE 裝置靠近 Mac 時，無須輸入密碼即可為你解鎖 Mac
- 當 BLE 裝置遠離 Mac 時鎖定 Mac
- 可選擇在鎖定／解鎖時執行自訂指令稿
- 可選擇從螢幕睡眠中喚醒
- 可選擇在離開及返回時暫停與繼續播放音樂／影片
- 密碼會安全地儲存在鑰匙圈

## 系統需求

- 支援 Bluetooth Low Energy 的 Mac
- macOS 10.13（High Sierra）或更新版本
- iPhone 5s 或更新機型、任何 Apple Watch，或其他具有[固定 MAC 位址](#關於-mac-位址)並定期傳送訊號的 BLE 裝置

## 安裝

### 使用 Homebrew Cask

下列 Homebrew Cask 是上游版本，可能不包含此 fork 的新增功能：

```
brew install bleunlock
```

若要使用此 fork 的功能，請參閱下方的[從原始碼編譯](#從原始碼編譯)。

### 手動安裝

從上游的 [Releases](https://github.com/ts1/BLEUnlock/releases) 下載 zip 檔、解壓縮後移至「應用程式」資料夾。此上游版本可能不包含此 fork 的新增功能；fork 使用者請改依[從原始碼編譯](#從原始碼編譯)操作。

## 初始設定

第一次啟動時，程式會要求下列權限，請務必允許：

權限 | 說明
-----------|---
藍牙 | 顯然需要藍牙存取權。請選擇 *好*。
輔助使用 | 這是用來解鎖鎖定畫面所必需。按一下 *打開系統設定*，按左下方的鎖頭圖示解鎖，然後啟用 BLEUnlock。
鑰匙圈 | （不一定會詢問）如果出現提示，必須選擇 **永遠允許**，因為螢幕鎖定時仍需要此權限。
通知 | （選用）BLEUnlock 鎖定螢幕時會在鎖定畫面顯示訊息，有助於確認程式是否正常運作。此外，若要在鎖定畫面看到訊息，必須在「通知」偏好設定中將 *顯示預覽* 設為 *永遠*。

> 注意：每個版本的 macOS 所需權限都會增加；若你使用較舊的作業系統，可能不會被要求一項或多項權限。

接著程式會詢問你的登入密碼以解鎖鎖定畫面。
密碼會安全地儲存在鑰匙圈中。

最後，從選單列圖示選擇 *裝置*。
程式會開始掃描附近的 BLE 裝置。
選取你的裝置後，設定即完成！

對於受支援的 Apple 裝置，當使用者命名與偵測到的硬體型號皆可取得時，BLEUnlock 會將兩者合併顯示，例如 `Fred's iPhone (iPhone 16 Pro Max)`。若只有 `iPhone` 或 `iPad` 這類通用名稱，BLEUnlock 會改為顯示偵測到的型號。

## Telegram 通知

Telegram 通知是選用功能；在設定並啟用前會維持停用：

1. 使用 [@BotFather](https://t.me/BotFather) 建立機器人，並複製其 Token。
2. 傳送一則訊息給該機器人，接著開啟 `https://api.telegram.org/bot<TOKEN>/getUpdates`，從回應中複製數字型 Chat ID。
3. 開啟 *BLEUnlock > Telegram Notifications > Configure…*，並儲存這兩個值。
4. 傳送測試通知、選擇事件開關，然後啟用 Telegram。
5. 若啟用照片警示，macOS 詢問時請允許相機存取權。

核准的事件預設值為 `away`、`lost`、`intruded` 開啟，`unlocked` 關閉。Telegram 本身預設為停用。`intruded` 的拍照預設為開啟；只有 `intruded` 事件可附加照片，其他事件通知皆只有文字。若拒絕相機權限或拍照失敗，`intruded` 警示仍會以純文字送出。每張暫存的入侵照片都會在每次傳送嘗試後刪除，不論該次傳送成功或失敗。

若為照片警示啟用可選的 Mac 定位功能，照片說明文字會包含座標、精確度與 Apple 地圖連結，之後會再傳送一則原生 Telegram 位置訊息。若定位資訊無法取得，照片仍會送出，並帶有定位無法使用的說明文字；不會傳送地圖訊息。

舊有的 `~/Library/Application Scripts/jp.sone.BLEUnlock/event` 指令稿仍可使用，且不受 Telegram 影響，會繼續個別接收全部四種事件引數。

## 選項

選項 | 說明
-------|---
立即鎖定螢幕 | 不論 BLE 裝置是否在附近都會鎖定螢幕；裝置先遠離、再靠近時才會解鎖。這可確保你離開座位前螢幕已鎖定。
解鎖 RSSI | 用於解鎖的藍牙訊號強度。數值越大，表示 BLE 裝置必須更靠近 Mac 才會解鎖。選擇 *停用* 可關閉解鎖功能。為提高穩定性，候選解鎖會從此門檻低 5 dB 處開始；在 1.5 秒內最多三筆讀值中，必須有兩筆符合條件才會確認。只有一般模式會進行 0.4 秒的突發讀取；被動模式持續使用廣播，不會建立突發連線。
鎖定 RSSI | 用於鎖定的藍牙訊號強度。數值越小，表示 BLE 裝置必須離 Mac 更遠才會鎖定。選擇 *停用* 可關閉鎖定功能。
鎖定前延遲 | 偵測到 BLE 裝置遠離後，鎖定 Mac 前的等待時間。若裝置在此時間內再次靠近，就不會鎖定。
無訊號逾時 | 從最後一次接收訊號到鎖定之間的時間。若經常因「訊號遺失」而鎖定，請增加此值。
接近時喚醒 | 鎖定時 BLE 裝置靠近，便從睡眠中喚醒顯示器。
喚醒但不解鎖 | 無論是由「接近時喚醒」自動喚醒或手動喚醒顯示器，BLEUnlock 都不會解鎖 Mac。這可相容 macOS 內建的 Apple Watch 解鎖功能（可在 BLEUnlock 喚醒螢幕後立即運作），也適合只想更快看到鎖定畫面而不想自動解鎖的情況。
鎖定時暫停「播放中」 | 鎖定／解鎖時，BLEUnlock 會暫停／繼續播放由 *播放中* 小工具或鍵盤 ⏯ 鍵控制的音樂或影片（包括 Apple Music、QuickTime Player 與 Spotify）。
使用螢幕保護程式鎖定 | 設定此選項後，BLEUnlock 會啟動螢幕保護程式而非直接鎖定。為使此選項正常運作，需在「安全性與隱私權」偏好設定中將 *進入睡眠或啟動螢幕保護程式後需要密碼* 設為 **立即**。
鎖定時關閉螢幕 | 鎖定時立即關閉顯示器。
設定密碼… | 若你變更登入密碼，請使用此功能。
被動模式 | 預設會主動嘗試連線至 BLE 裝置並讀取 RSSI。多數情況建議使用預設值，且運作穩定；但若使用藍牙鍵盤、滑鼠、觸控板，尤其是藍牙個人熱點，預設模式可能彼此干擾，2.4GHz Wi‑Fi 也可能造成干擾。若藍牙不穩定，請開啟被動模式。
登入時啟動 | 登入時啟動 BLEUnlock。
設定最小 RSSI | RSSI 低於此值的裝置不會顯示在裝置掃描列表中。

## 疑難排解

### 裝置沒有出現在列表中

若你的 BLE 裝置不是 Apple 裝置，BLEUnlock 可能無法辨識裝置名稱。
此時會以 UUID（長串十六進位數字與連字號）顯示裝置。
要辨識裝置，請嘗試讓裝置靠近或遠離 Mac，並查看 RSSI（dB 值）是否隨之變化。

若列表中完全沒有任何裝置，請嘗試依下述方式重設藍牙模組。

### 無法解鎖

確認已在 *系統設定* > *安全性與隱私權* > *隱私權* > *輔助使用* 中啟用 BLEUnlock。
若已啟用，請嘗試先關閉再重新開啟。

若程式要求在鑰匙圈中存取自己的密碼，必須選擇 *永遠允許*，因為螢幕鎖定時仍需要該密碼。

### 經常出現「訊號遺失」

請增加 *無訊號逾時*。
或者嘗試使用 *被動模式*。

### 藍牙鍵盤、滑鼠、個人熱點或其他藍牙裝置異常

首先，在選單列或控制中心按住 Shift + Option 再按藍牙圖示，然後按一下 *重設藍牙模組*。

在 macOS 12 Monterey 中，此選項已不再提供。
請改在終端機輸入下列指令以重設藍牙模組：

```
sudo pkill bluetoothd
```

這個指令會要求輸入你的登入密碼。

若問題持續，請開啟 *被動模式*。

## 關於 MAC 位址

不同於傳統藍牙，Bluetooth Low Energy 裝置可使用*私有* MAC 位址。
該私有位址可能是隨機的，也可能不時變更。

近年的智慧裝置（iOS 與 Android）傾向使用約每 15 分鐘變更一次的私有位址，這可能是為了防止追蹤。

另一方面，BLEUnlock 要追蹤你的裝置，其 MAC 位址必須是固定的。

幸運的是，對於與 Mac 使用相同 Apple ID 登入的 Apple 裝置，MAC 位址會解析為真正的（公開）位址。

至於包括 Android 在內的其他裝置，目前不知道如何解析該位址。
若非 Apple 裝置的 MAC 位址會隨時間變更，很遺憾 BLEUnlock 無法支援。

要確認 MAC 位址是否正確解析，請比較 BLEUnlock *裝置* 掃描列表中顯示的 MAC 位址，與裝置上顯示的 MAC 位址。

## 鎖定／解鎖時執行指令稿

鎖定與解鎖時，BLEUnlock 會執行位於以下路徑的指令稿：

```
~/Library/Application Scripts/jp.sone.BLEUnlock/event
```

會依事件類型傳入一個引數：

|事件|引數|
|-----|--------|
|BLEUnlock 因 RSSI 過低而鎖定|`away`|
|BLEUnlock 因沒有訊號而鎖定|`lost`|
|BLEUnlock 解鎖|`unlocked`|
|手動解鎖|`intruded`|

> 注意：要讓 `intruded` 事件正確運作，必須在「安全性與隱私權」偏好設定中將 *進入睡眠後需要密碼* 設為 **立即**。

### 歷史 LINE Notify 範例（已不支援）

本 README 的舊版本曾在此提供 LINE Notify 與 SnapshotUnlocker 指令稿。LINE Notify 已停止服務，因此該歷史端點與範例不受支援，且已無法運作。請改用 BLEUnlock 內建的 Telegram 通知，或透過舊有的 `event` 指令稿串接其他現行服務。

## 從原始碼編譯

在 Xcode 開啟 `BLEUnlock.xcodeproj`，並建置 `BLEUnlock` scheme。Release 建置會直接輸出至：

```
build/Release/BLEUnlock.app
```

Debug 建置會輸出至 `build/Debug/BLEUnlock.app`。中繼建置資料會保留在 Xcode 的 Derived Data 目錄，而最終 App 會保留在專案已忽略的 `build/` 目錄下。

App 版本與建置號碼由 Xcode 的 `MARKETING_VERSION` 與 `CURRENT_PROJECT_VERSION` 設定管理。來源 `Info.plist` 會參照這些設定，且建置期間不會遭修改，因此可維持啟用 Xcode 的 User Script Sandboxing。

## 贊助原作者

年度 Apple Developer Program 費用由捐款支應。

若你喜歡這個 App，歡迎透過 [Buy Me a Coffee](https://www.buymeacoffee.com/tsone) 或 [PayPal Me](https://www.paypal.com/paypalme/my/profile) 捐款。這些既有連結用於支持原始作者 Takeshi Sone，協助他持續維護上游專案。

## 致謝

- [peiit](https://github.com/peiit)：中文翻譯
- [wenmin-wu](https://github.com/wenmin-wu)：最小 RSSI 與移動平均
- [stephengroat](https://github.com/stephengroat)：CI
- [joeyhoer](https://github.com/joeyhoer)：Homebrew Cask
- [Skyearn](https://github.com/Skyearn)：Big Sur 風格圖示
- [cyberclaus](https://github.com/cyberclaus)：德文、瑞典文、挪威文（Bokmål）與丹麥文在地化
- [alonewolfx2](https://github.com/alonewolfx2)：土耳其文在地化
- [wernjie](https://github.com/wernjie)：喚醒但不解鎖
- [tokfrans03](https://github.com/tokfrans03)：語言修正

圖示以從 materialdesignicons.com 下載的 SVG 為基礎。
原始設計者為 Google LLC，並依 Apache License 2.0 授權。

## 授權

本專案依 [MIT License](LICENSE) 授權發布。

- 原始程式：Copyright © 2019–2022 Takeshi Sone
- 此 fork 的 2026 年修改：Copyright © 2026 fred-lede

完整授權條款請參閱 [LICENSE](LICENSE)。原作者的版權聲明已保留，未被此 fork 的聲明取代。
