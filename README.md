# TransReaderSwift

Swift 原生 macOS 翻译应用，完全重写自 Python 版 TransReader。

## 当前进度

### ✅ 已完成 (Phase 1-4)

#### Phase 1: 项目脚手架 + 核心
- ✅ Swift Package with .executableTarget (macOS 14+)
- ✅ 使用 @main App + MenuBarExtra 菜单栏应用
- ✅ 数据模型: Sentence, TranslationResult, Config, VocabEntry, Chunk, Analysis
- ✅ ConfigStore: 读写 ~/.transreader/config.json，完全兼容 Python 版格式
- ✅ Provider 配置: DeepSeek, MiniMax, GLM (OpenAI-compatible API)

#### Phase 2: 翻译引擎
- ✅ OpenAI-compatible streaming API 调用 (URLSession + AsyncBytes)
- ✅ 流式 JSON 解析: 逐句提取 {en, zh, analysis} 对象
- ✅ analysis 包含: structure, tense, chunks (递归 children), tip
- ✅ 翻译队列: 串行执行，支持取消
- ✅ System prompt 从 Python 版 translator.py 的 DEFAULT_SYSTEM_PROMPT 原样复制

#### Phase 3: SwiftUI 主界面
- ✅ MenuBarExtra 菜单栏图标"译"
- ✅ 菜单项: 截取翻译、显示/隐藏窗口、窗口置顶、划词监控开关(占位)、AI 服务商切换、设置、退出
- ✅ 主窗口 SwiftUI:
  - ✅ 翻译结果展示: 逐句显示 en + zh + 可折叠语法分析
  - ✅ 语法分析: 显示 structure、tense、tip，chunks 用缩进树展示（支持递归 children）
  - ✅ 翻译历史列表（最近 50 条）
  - ✅ 流式翻译: partial 先显示 en+zh，complete 后展示完整分析
- ✅ 设置页面:
  - ✅ AI 服务商选择 + API Key 输入
  - ✅ 划词监控间隔
  - ✅ 请求超时
  - ✅ 剪贴板翻译开关
  - ✅ 排除应用列表
  - ✅ 排除 URL 列表
  - ✅ System prompt 编辑
  - ✅ 快捷键设置 (占位)
  - ✅ 生词本路径

#### Phase 4: OCR 截屏翻译
- ✅ 调用 screencapture -i -x -s 截取屏幕区域
- ✅ Vision framework VNRecognizeTextRequest OCR
- ✅ 识别结果 → 翻译队列
- ✅ 处理换行连字符合并 (_join_lines)

### 🚧 待实现 (Phase 5-7)

#### Phase 5: 划词监控
- ⬜ AXUIElementCreateSystemWide + AXSelectedText 轮询
- ⬜ 检测焦点应用，过滤排除列表
- ⬜ 浏览器 URL 检测 (AppleScript)
- ⬜ Electron/WebView apps 的 Cmd+C 回退
- ⬜ 剪贴板变化检测
- ⬜ 单词 vs 句子分流: 单词走词典查询，句子走翻译

#### Phase 6: 词典 + 生词本
- ⬜ 有道词典 API (jsonapi_s)
- ⬜ AI 回退查词
- ⬜ 词典卡片 UI: 音标、释义、例句、近义词
- ⬜ 生词本 CRUD，存储为 .canvas JSON 文件
- ⬜ 生词本 UI: 列表、搜索、添加、删除

#### Phase 7: 全局快捷键
- ⬜ NSEvent.addGlobalMonitorForEventsMatchingMask 注册全局热键
- ⬜ 可配置快捷键（和 Python 版 shortcuts 格式兼容）

## 构建 & 运行

```bash
cd ~/data/code/TransReaderSwift
swift build
swift run
```

## 技术栈

- Swift 5.10+
- macOS 14+ (Sonoma+)
- SwiftUI for UI
- AppKit for window management, NSEvent, AX API
- Vision framework for OCR
- URLSession for networking (async/await)
- @Observable for state management
- 零第三方依赖

## 配置文件位置

- `~/.transreader/config.json` - 主配置（和 Python 版兼容）
- `~/.transreader/vocab.canvas` - 生词本（JSON 格式）

## 注意事项

- 首次运行需要授予屏幕录制权限（截图功能）
- 划词监控需要辅助功能权限（尚未实现）
- Config 文件格式 100% 兼容 Python 版，可以直接共享配置

## 下一步

1. 实现 Phase 5 划词监控（核心功能）
2. 实现 Phase 6 词典 + 生词本
3. 实现 Phase 7 全局快捷键
4. 性能优化和错误处理
5. 单元测试
6. 打包为 .app
