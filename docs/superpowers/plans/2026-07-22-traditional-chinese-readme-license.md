# Traditional Chinese README and MIT License Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a complete Traditional Chinese README for this fork and a detectable MIT License file that preserves upstream attribution while identifying the fork maintainer's modifications.

**Architecture:** Keep the English README authoritative for the shared feature reference and add `README_CHT.md` as its complete Traditional Chinese counterpart with an explicit fork notice. Put the canonical MIT terms in a root `LICENSE` file, then link the English and Traditional Chinese documents without touching application source or Xcode settings.

**Tech Stack:** Markdown, standard MIT License text, Git, shell-based documentation assertions.

## Global Constraints

- Preserve the upstream project link `https://github.com/ts1/BLEUnlock` and identify Takeshi Sone as the original author.
- Identify `fred-lede` as the fork maintainer and copyright holder for 2026 fork modifications.
- Do not remove or replace `Copyright (c) 2019-2022 Takeshi Sone`.
- State that upstream Homebrew and upstream releases may not contain fork-specific additions.
- Retain existing third-party credits and the Apache License 2.0 icon attribution.
- Translate all current English README sections; do not omit permissions, troubleshooting, event-script, or build-output details.
- This documentation change must not modify application source files or Xcode-project settings.
- Leave the existing untracked `.codegraph/` directory untouched and uncommitted.

---

### Task 1: Add the canonical MIT license

**Files:**
- Create: `LICENSE`

**Interfaces:**
- Consumes: the upstream copyright statement currently in `README.md`.
- Produces: the root MIT `LICENSE` file linked by Task 2.

- [ ] **Step 1: Record the missing-file baseline**

Run:

```bash
test -f LICENSE
```

Expected: exit status 1 because the repository has no root license file.

- [ ] **Step 2: Create the complete MIT license file**

Create `LICENSE` with exactly this text:

```text
MIT License

Copyright (c) 2019-2022 Takeshi Sone
Copyright (c) 2026 fred-lede

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Verify the license text**

Run:

```bash
rg -n '^Copyright \(c\) 2019-2022 Takeshi Sone$|^Copyright \(c\) 2026 fred-lede$|^Permission is hereby granted|^THE SOFTWARE IS PROVIDED "AS IS"' LICENSE
```

Expected: four matching lines: both copyright notices, the permission opening, and the warranty opening. Manually confirm the full license matches the text in Step 2 byte-for-byte.

- [ ] **Step 4: Commit the license foundation**

```bash
git diff --check
git add LICENSE
git commit -m "Add MIT license for fork modifications"
```

---

### Task 2: Add the complete Traditional Chinese README

**Files:**
- Create: `README_CHT.md`
- Modify: `README.md:11`

**Interfaces:**
- Consumes: every user-facing section of `README.md`, the root `LICENSE` from Task 1, and the approved fork attribution design.
- Produces: the repository's complete Traditional Chinese entry document.

- [ ] **Step 1: Confirm the translated document and English language link are absent**

Run:

```bash
test -f README_CHT.md
```

Expected: exit status 1.

Run:

```bash
rg -F '[Traditional Chinese (繁體中文)](README_CHT.md)' README.md
```

Expected: exit status 1 with no match.

- [ ] **Step 2: Add the Traditional Chinese language link to the English README**

Replace the existing language sentence with:

```markdown
This document is also available in [Japanese (日本語版はこちら)](README.ja.md) and [Traditional Chinese (繁體中文)](README_CHT.md).
```

- [ ] **Step 3: Write the identity and fork notice at the top of `README_CHT.md`**

Begin the file with this content, followed by the existing upstream badges:

```markdown
# BLEUnlock

> [!IMPORTANT]
> 本專案是 [ts1/BLEUnlock](https://github.com/ts1/BLEUnlock) 的 fork。原始作者為 Takeshi Sone；此 fork 由 [fred-lede](https://github.com/fred-lede) 維護。
>
> 此 fork 已修改程式碼與 Xcode 專案，主要新增繁體中文介面、Telegram 通知、可選的入侵拍照與 Mac 定位資訊、Apple 裝置名稱與掃描改善、相機預熱，以及較穩定的接近確認機制。上游 Homebrew Cask 與上游 Releases 不一定包含這些功能；若要使用此 fork 的功能，請從本儲存庫原始碼編譯，除非此 fork 另有發布 Release。

本文件亦提供[英文版](README.md)與[日文版](README.ja.md)。
```

Preserve these badges immediately after the notice because they describe the upstream project and funding link; explain in the Funding section that the donation links support the original author:

```markdown
![CI](https://github.com/ts1/BLEUnlock/workflows/CI/badge.svg)
![Github All Releases](https://img.shields.io/github/downloads/ts1/BLEUnlock/total.svg)
[![Buy me a coffee](img/buymeacoffee.svg)](https://www.buymeacoffee.com/tsone)
```

- [ ] **Step 4: Translate every README section with fixed heading coverage**

Use the current English paragraphs, lists, tables, commands, paths, defaults, warnings, and links as the source of truth. Use exactly these Traditional Chinese headings so coverage is reviewable:

```markdown
## 重要說明：本應用程式未在 Mac App Store 發布，可免費取得
## 功能
## 系統需求
## 安裝
### 使用 Homebrew Cask
### 手動安裝
## 初始設定
## Telegram 通知
## 選項
## 疑難排解
### 裝置沒有出現在列表中
### 無法解鎖
### 經常出現「訊號遺失」
### 藍牙鍵盤、滑鼠、個人熱點或其他藍牙裝置異常
## 關於 MAC 位址
## 鎖定／解鎖時執行指令稿
### 歷史 LINE Notify 範例（已不支援）
## 從原始碼編譯
## 贊助原作者
## 致謝
## 授權
```

Translation rules:

- Keep `brew install bleunlock`, `sudo pkill bluetoothd`, the application-script path, event arguments, and `build/Release/BLEUnlock.app` exactly unchanged.
- Preserve the permission, option, and event tables with all rows from `README.md`.
- Preserve the documented Telegram defaults: `away`, `lost`, and `intruded` enabled; `unlocked` disabled; Telegram disabled until configured; only `intruded` can attach a photo; temporary photos are deleted after each send attempt.
- Document the optional Mac-location setting: when enabled for a photo alert, the caption includes coordinates, accuracy, and an Apple Maps link, followed by a native Telegram location message; if location is unavailable, the photo still sends with an unavailable-location caption and no map message.
- Preserve the Apple-device naming example `Fred's iPhone (iPhone 16 Pro Max)` and explain the generic-name fallback.
- Explain the fork's stable proximity behaviour beside Unlock RSSI: a candidate starts 5 dB below the unlock threshold, confirmation requires two qualifying samples among at most three within 1.5 seconds, and only normal mode performs 0.4-second burst reads; passive mode continues using advertisements without burst connections.
- In Installation, label Homebrew and the upstream Releases link as upstream builds that may omit fork additions. Add a sentence directing fork users to the source-build section.
- In Funding, state that the existing Buy Me a Coffee and PayPal links support original author Takeshi Sone.
- Keep every named contributor and the Google LLC / Apache License 2.0 icon attribution.

- [ ] **Step 5: Add the exact Traditional Chinese license section**

End `README_CHT.md` with:

```markdown
## 授權

本專案依 [MIT License](LICENSE) 授權發布。

- 原始程式：Copyright © 2019–2022 Takeshi Sone
- 此 fork 的 2026 年修改：Copyright © 2026 fred-lede

完整授權條款請參閱 [LICENSE](LICENSE)。原作者的版權聲明已保留，未被此 fork 的聲明取代。
```

- [ ] **Step 6: Validate section coverage, attribution, links, and change scope**

Run:

```bash
rg -n '^## |^### ' README_CHT.md
```

Expected: every heading listed in Step 4 appears exactly once and in the same functional order as `README.md`.

Run:

```bash
rg -n 'ts1/BLEUnlock|Takeshi Sone|fred-lede|README.md|README.ja.md|MIT License|LICENSE|Apache License 2.0|build/Release/BLEUnlock.app' README_CHT.md
```

Expected: all attribution, language, license, third-party credit, and build-output references are present.

Run:

```bash
rg -F '[Traditional Chinese (繁體中文)](README_CHT.md)' README.md
```

Expected: one matching language-link line.

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only `README.md` and `README_CHT.md` changed after the Task 1 commit, plus the pre-existing untracked `.codegraph/` directory.

- [ ] **Step 7: Review the rendered Markdown**

Open `README_CHT.md` in a Markdown preview and confirm:

- the fork notice renders as an important callout;
- all tables have aligned headers and rows;
- ordered lists retain their numbering;
- code blocks are closed and display the intended commands;
- relative links to `README.md`, `README.ja.md`, and `LICENSE` resolve; and
- upstream badges, contributor links, Telegram links, and donation links are not broken.

- [ ] **Step 8: Commit the Traditional Chinese guide**

```bash
git add README.md README_CHT.md
git commit -m "Add Traditional Chinese README"
```

---

### Task 3: Final documentation audit

**Files:**
- Verify: `README.md`
- Verify: `README_CHT.md`
- Verify: `LICENSE`

**Interfaces:**
- Consumes: the two documentation commits from Tasks 1 and 2.
- Produces: review evidence that the fork attribution, translation, and MIT obligations are complete without source-code changes.

- [ ] **Step 1: Compare English and Traditional Chinese section coverage**

Run:

```bash
rg '^## |^### ' README.md README_CHT.md
```

Expected: every English functional section has a corresponding Traditional Chinese section; the Traditional Chinese document additionally contains the explicit fork framing required by the design.

- [ ] **Step 2: Confirm the final commit range changes only documentation and licensing files**

Run from the commit immediately before Task 1:

```bash
git diff --name-only HEAD~2..HEAD
```

Expected exactly:

```text
LICENSE
README.md
README_CHT.md
```

- [ ] **Step 3: Run final repository checks**

```bash
git diff --check HEAD~2..HEAD
git status --short
```

Expected: no whitespace errors. Working-tree status contains no documentation changes; the pre-existing `.codegraph/` directory may remain untracked.

- [ ] **Step 4: Record the legal handling in the handoff**

The handoff must state:

- MIT permits use, modification, redistribution, sublicensing, and sale subject to retaining the copyright and permission notice;
- the repository now keeps the original Takeshi Sone notice and the `fred-lede` modification notice in `LICENSE`;
- the fork and upstream release distinction is explicit in `README_CHT.md`; and
- this is practical repository-maintenance guidance, not individualized legal advice.
