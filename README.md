<h1 align="center">中日英辞典</h1>

<p align="center">
  专为<b>学日语、学英语的中文用户</b>做的 Mac 查词翻译小工具<br>
  看到不认识的词，选中它、截个图，或者直接输入，马上就有中、日、英三种语言的解释
</p>

<p align="center">
  <a href="../../releases/latest"><b>⬇︎ 下载最新版</b></a>
  &nbsp;·&nbsp; 免费 &nbsp;·&nbsp; 支持 macOS 14 及以上（Apple 芯片和 Intel 都可以）
</p>

<p align="center">
  <a href="../../releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/FinnKyo/mac-trilingual-dict?color=3E5C82&label=最新版本"></a>
  <img alt="platform" src="https://img.shields.io/badge/macOS-14%2B-3E5C82">
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-GPL--3.0-3E5C82"></a>
</p>

## 三种用法

### 划词翻译：选中文字，鼠标移到小图标上

读网页、看文档时遇到生词，选中它，旁边会出现一个小图标，把鼠标移上去，翻译就出来了。划到的内容不对也没关系，可以在窗口里直接改。

<p align="center"><img src="docs/demo-selection.gif" width="660" alt="划词翻译演示"></p>

### 截图翻译：按 ⌥S，框住图片里的文字

漫画、游戏、视频字幕、图片里的字没法选中？按 `⌥S`（Option + S）框住它，自动识别文字并翻译，日文还会标上假名。

<p align="center"><img src="docs/demo-screenshot.gif" width="660" alt="截图翻译演示"></p>

### 输入查词：按 ⌥A，直接输入

随时按 `⌥A`（Option + A）打开查词窗口，输入中文、英文或日文都可以。

<p align="center"><img src="docs/demo-input.gif" width="660" alt="输入查词演示"></p>

<sub>演示中的阅读窗口和图片是示意画面，查词窗口和结果是 App 的真实界面。</sub>

## 查词结果长什么样

<table>
  <tr>
    <th align="center">日语单词</th>
    <th align="center">英语单词</th>
    <th align="center">中文查日语、英语</th>
    <th align="center">整句翻译</th>
  </tr>
  <tr>
    <td><picture><source media="(prefers-color-scheme: dark)" srcset="docs/shot-ja-dark.png"><img src="docs/shot-ja-light.png" width="220" alt="日语单词"></picture></td>
    <td><picture><source media="(prefers-color-scheme: dark)" srcset="docs/shot-en-dark.png"><img src="docs/shot-en-light.png" width="220" alt="英语单词"></picture></td>
    <td><picture><source media="(prefers-color-scheme: dark)" srcset="docs/shot-zh-dark.png"><img src="docs/shot-zh-light.png" width="220" alt="中文查日语、英语"></picture></td>
    <td><picture><source media="(prefers-color-scheme: dark)" srcset="docs/shot-sentence-dark.png"><img src="docs/shot-sentence-light.png" width="220" alt="整句翻译"></picture></td>
  </tr>
</table>

## 它好在哪里

- **一次看三种语言**：查日语，同时给中文和英文；查英语，同时给中文和日语；查中文，告诉你日语、英语分别怎么说。
- **日语查得细**
  - 单词的读音、声调、罗马音、JLPT 等级一目了然
  - 每个意思都配了例句，例句标好了假名、附中文翻译
  - 单词和例句都能**听真人发音**
  - 还附上日本的国语辞典《デジタル大辞泉》的日文解释，适合进阶学习
  - 「食べた」「食べさせられた」这类变形会自动找到原形「食べる」
- **英语查得全**：英式、美式音标和发音，四六级、考研、GRE 等考试标签，词形变化，常用短语，双语例句。
- **日文自动标假名**：原文和译文里的日文都会标好假名，不用再去查读音。
- **中文和日语分得清**：日语和中文都用汉字，App 会自动判断是哪种语言；万一判断错了，点一下「按日语查 / 按中文查」就能切换。
- **点一下继续查**：释义里的单词、相关词条都可以直接点开，还能返回上一个词。
- **不打扰**：住在菜单栏里，不占 Dock；支持浅色和深色模式。

## 下载和安装

1. 到 [下载页面](../../releases/latest) 下载 `DictTranslator-x.y.z.zip`，双击解压，把 `DictTranslator.app` 拖进「应用程序」文件夹。
2. 第一次打开时，系统可能会提示 **「已损坏，无法打开」** 或 **「无法验证开发者」**。
   这是因为这个免费小工具没有向 Apple 付费做认证，**并不是文件真的坏了**。按下面的方法放行一次就好：
   - 打开 **系统设置 › 隐私与安全性**，往下滚到底，点击 **「仍要打开」**，再确认一次。
   - 如果没看到这个按钮，可以打开「终端」，粘贴下面这行后按回车：
     ```bash
     xattr -dr com.apple.quarantine /Applications/DictTranslator.app
     ```
3. 打开后会出现设置窗口，按提示允许两项权限：
   - **辅助功能**：用来读取你在其他 App 里选中的文字（划词翻译、⌥D 需要）。
   - **屏幕与系统音频录制**：用来截图识别文字（⌥S 需要）。允许后需要退出 App 再打开一次。

   这两项权限只用来读取你选中的文字和你框选的那一块截图。截图在本机识别文字，识别完立即删除，图片不会上传；识别出来的文字（和划词选中的文字）会发给词典、翻译服务用来查询。

更新版本时，下载新的压缩包，覆盖旧的 App 即可。

## 快捷键

| 按键 | 作用 |
|---|---|
| `⌥A` | 打开查词窗口，直接输入 |
| `⌥S` | 截图翻译：框住屏幕上的文字 |
| `⌥D` | 翻译当前选中的文字 |
| `Esc` | 关闭查词窗口 |

`⌥` 就是键盘上的 Option 键。快捷键可以在菜单栏图标 › 设置里修改。

小提示：
- 查词窗口默认点到别处就会关闭，点窗口右上角的图钉可以把它固定住。
- 划词时窗口会出现在选中的文字旁边；用快捷键打开时出现在屏幕右上角。
- 不想在某些 App 里弹出划词图标（比如终端、代码编辑器），可以在 设置 › 划词 里加进黑名单。

## 常见问题

<details>
<summary>已经在系统设置里允许了权限，App 里还是显示「未授权」</summary>

更新 App 之后，系统有时会把它当成一个新程序。到「系统设置 › 隐私与安全性 › 辅助功能」（或「屏幕与系统音频录制」）里，先选中「中日英辞典」点 **−** 删掉，再重新添加或勾选，然后退出 App 重新打开。
</details>

<details>
<summary>选中文字后没有出现小图标</summary>

- 确认已经允许了「辅助功能」权限，并且菜单栏图标菜单里的「划词翻译」是勾选状态。
- 当前的 App 可能在划词黑名单里（设置 › 划词），默认终端、Xcode、VS Code、访达不显示图标。
- 小图标几秒后会自动消失，可以在设置里把时间调长。
- 也可以选中文字后直接按 `⌥D`。
</details>

<details>
<summary>提示「查询失败」，或者句子没有翻译出来</summary>

查词和翻译需要联网。网络不好时可以点结果里的「重试」，或者在输入框里按回车再查一次。国内网络建议在 设置 › 通用 里选择「腾讯交互翻译优先」。
</details>

<details>
<summary>查词窗口里不能复制粘贴</summary>

请更新到 v1.2.1 或更新的版本。
</details>

## 说明

- 这是一个免费的个人学习工具，词典和翻译内容来自 MOJi 辞書、Weblio（デジタル大辞泉）、有道词典、Google 翻译、腾讯交互翻译，以及 macOS 自带的文字识别和语音朗读。
- 这些在线服务用的是它们网页版的接口，并不是官方开放的接口，以后可能会变化或暂时用不了。请仅用于个人学习，并遵守各服务的使用条款。

<details>
<summary><b>给开发者</b></summary>

### 从源码编译

需要 Xcode（Swift 5.10+）。

```bash
git clone https://github.com/FinnKyo/mac-trilingual-dict.git
cd mac-trilingual-dict
./build.sh            # 编译通用二进制、签名并安装到 /Applications
```

`build.sh` 会自动使用钥匙串里的 Apple Development / Developer ID 证书签名（重新编译后系统权限不会失效）；没有证书则使用临时签名，每次重新编译后需要重新授权辅助功能。只想编译不安装：`NO_INSTALL=1 ./build.sh`。

### 常用命令

```bash
swift test                                              # 解析、语言识别与网络接口测试
swift build && .build/debug/DictTranslator --render "食べた" out.png [--dark]   # 离屏渲染结果界面
.build/debug/DictTranslator --identify 语料.json         # 中日识别准确率评测（语料为 {"ja": [...], "zh": [...]}）
scripts/package.sh                                      # 生成 Release 用的 zip
scripts/demo/make_demo.sh                               # 重新生成 docs/ 里的演示动画和截图
```

`docs/` 里的演示图由 `scripts/demo/make_demo.sh` 生成：只截调试版 App 自己的窗口（不需要屏幕录制权限，不会拍到桌面），再放进 `scene.swift` 画的示意场景里。

### 数据来源

| 用途 | 来源 |
|---|---|
| 日语词条、汉日反查、日语单词 / 例句真人发音 | MOJi 辞書网页接口 |
| 日语国语辞典释义 | Weblio 辞書上的《デジタル大辞泉》（小学館） |
| 英语词条（英汉、汉英）、英语单词发音 | 有道词典网页接口 |
| 句子翻译 | Google 翻译网页接口 → 腾讯交互翻译（TranSmart）→ macOS 系统离线翻译，依次兜底；Google 被限流时自动暂停 |
| 句子朗读 | macOS 系统语音（离线） |
| 中 / 日语言识别（汉字文本） | 汉字字库归属（GB2312 / JIS）+ 系统 NaturalLanguage + 词典收录 + Google 语言检测 |
| 日文注音 | MOJi 例句自带注音；其余用系统日语分词器（CFStringTokenizer） |
| 截图文字识别 | Vision |

### 目录

```
Sources/DictTranslator/
  App/         菜单栏、主菜单、快捷键、权限、设置项
  Core/        语言识别（LanguageDetector / LanguageIdentifier）、词 / 句判定、查询状态（LookupViewModel）
  Services/    MOJi 辞書、Weblio（大辞泉）、有道词典、Google / 腾讯 / 系统翻译、假名注音、OCR、发音
  Selection/   划词监听、选中文字读取、小图标
  Screenshot/  截图翻译
  UI/          输入翻译窗、结果界面、词条视图、配色（Theme）、设置界面
scripts/       打包、演示图生成
```

第三方依赖：[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（MIT）。
</details>

## 许可证

[GPL-3.0](LICENSE)
