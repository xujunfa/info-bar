# InfoBar — 技术设计方案

## 1. 项目定位

一款 macOS Menu Bar 应用，在菜单栏以原生品质渲染实时数据 widget（折线图、数字、状态指示器等），点击后弹出浮窗展示详细信息。浮窗内容使用 WKWebView + React 渲染，获得 Web 生态的开发效率；菜单栏 widget 使用原生 AppKit 自定义绘制，获得像素级的渲染质量。

### 核心原则

- **Menu Bar 层 = 原生 Swift**：NSStatusItem + 自定义 NSView，CoreGraphics 绘图
- **Popup 详情层 = React**：WKWebView 加载本地 React SPA
- **Bridge 层 = 双向通信**：Swift → JS（evaluateJavaScript）、JS → Swift（WKScriptMessageHandler）

## 2. 技术选型

| 层 | 技术 | 理由 |
|---|---|---|
| App 生命周期 | SwiftUI App protocol + @main | macOS 13+ 标准做法，比 NSApplicationDelegate 更简洁 |
| Menu Bar 入口 | NSStatusItem（通过 AppKit 桥接） | SwiftUI MenuBarExtra 不支持自定义绘图 view，必须用 NSStatusItem |
| Widget 渲染 | NSView + draw(_:) + NSBezierPath | 参考 Stats 的做法，这是 menu bar 内自定义图形的唯一可靠方式 |
| 弹窗容器 | NSWindow + NSVisualEffectView | 原生毛玻璃 + 无标题栏浮窗，与系统风格一致 |
| 弹窗内容 | WKWebView + React | Web 生态图表库丰富（ECharts/Recharts/D3），开发效率高 |
| 通信 | WKScriptMessageHandler + evaluateJavaScript | 原生双向桥接，无需第三方依赖 |
| 数据层 | Swift async/await + Combine | 现代 Swift 并发模型 |
| 持久化 | UserDefaults / @AppStorage | 轻量配置存储 |
| 最低系统 | macOS 13 Ventura | 覆盖主流用户，可用 SwiftUI 4+ 和 async/await 全部特性 |
| Swift 版本 | Swift 5.9+ | 支持 macros、parameter packs 等现代特性 |

## 3. 项目结构

```
InfoBar/
├── InfoBarApp.swift              # @main 入口，App protocol
├── AppState.swift                # 全局状态（ObservableObject）
│
├── MenuBar/                      # ====== 菜单栏层（纯 AppKit）======
│   ├── StatusItemManager.swift   # NSStatusItem 生命周期管理
│   ├── MenuBarView.swift         # 容纳多个 widget 的 NSView 容器
│   ├── Widgets/                  # 各类 menu bar widget
│   │   ├── WidgetProtocol.swift  # widget 通用协议
│   │   ├── WidgetBase.swift      # NSView 基类，宽度管理
│   │   ├── MiniWidget.swift      # 紧凑数字显示（如 "42%"）
│   │   ├── LineChartWidget.swift # 迷你折线图
│   │   ├── BarChartWidget.swift  # 迷你柱状图
│   │   └── LabelWidget.swift    # 纯文字标签
│   └── Drawing/
│       └── ChartRenderer.swift   # 共享的 CoreGraphics 绘图工具函数
│
├── Popup/                        # ====== 弹窗层（AppKit + WebView）======
│   ├── PopupWindow.swift         # NSWindow 子类，浮窗行为
│   ├── PopupPositioner.swift     # 弹窗定位算法（屏幕边界处理）
│   ├── PopupViewController.swift # 管理 header + WKWebView
│   └── PopupHeaderView.swift     # 原生标题栏（标题 + 设置按钮）
│
├── Bridge/                       # ====== Swift ↔ JS 通信层 ======
│   ├── WebViewManager.swift      # WKWebView 配置与生命周期
│   ├── NativeBridge.swift        # Swift → JS：推送数据
│   └── JSMessageHandler.swift    # JS → Swift：接收消息并分发
│
├── Data/                         # ====== 数据采集层 ======
│   ├── DataProvider.swift        # 数据源协议（async 接口）
│   ├── Providers/                # 各类数据源实现
│   │   └── ...
│   └── DataScheduler.swift       # 定时采集调度器
│
├── Settings/                     # ====== 设置层（SwiftUI）======
│   ├── SettingsView.swift        # 设置窗口主视图
│   └── ...
│
├── Resources/
│   └── WebApp/                   # React 打包产物
│       ├── index.html
│       └── assets/
│
└── react-app/                    # React 源码（独立工程）
    ├── package.json
    ├── src/
    │   ├── App.tsx
    │   ├── bridge.ts             # JS 侧桥接封装
    │   ├── components/
    │   └── hooks/
    ├── vite.config.ts
    └── tsconfig.json
```

## 4. 核心模块设计

### 4.1 Menu Bar Widget 渲染

这是 InfoBar 体验的核心。参考 Stats 的 `Kit/module/widget.swift` 和 `Kit/plugins/Charts.swift` 中验证过的模式，使用现代 Swift 重新实现。

#### Widget 协议

```swift
import AppKit

protocol MenuBarWidget: NSView {
    /// Widget 当前需要的宽度（动态变化）
    var contentWidth: CGFloat { get }
    /// 宽度变化时的回调，通知容器重新布局
    var onWidthChanged: (() -> Void)? { get set }
    /// 点击回调
    var onClick: (() -> Void)? { get set }
}
```

#### Widget 基类

```swift
class WidgetBase: NSView, MenuBarWidget {
    var contentWidth: CGFloat = 0
    var onWidthChanged: (() -> Void)?
    var onClick: (() -> Void)?

    /// 安全地更新宽度，仅在变化时触发回调
    func updateWidth(_ newWidth: CGFloat) {
        guard contentWidth != newWidth else { return }
        contentWidth = newWidth
        Task { @MainActor in
            self.setFrameSize(NSSize(width: newWidth, height: self.frame.height))
            self.onWidthChanged?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?() ?? super.mouseDown(with: event)
    }
}
```

#### 折线图 Widget 示例（关键绘图逻辑）

Stats 在 `Kit/plugins/Charts.swift:172-275` 中的核心绘图模式：

```swift
class LineChartWidget: WidgetBase {
    private var values: [Double?] = Array(repeating: nil, count: 60)
    private var color: NSColor = .controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)

        let offset = 1.0 / (NSScreen.main?.backingScaleFactor ?? 1)
        let height = frame.height - offset
        let points = values.compactMap { $0 }
        guard points.count > 1 else { return }

        let maxVal = points.max() ?? 1
        let xStep = frame.width / CGFloat(values.count - 1)

        // 构建路径
        let path = NSBezierPath()
        var started = false
        for (i, v) in values.enumerated() {
            guard let v else { continue }
            let y = (v / maxVal) * height
            let point = CGPoint(x: CGFloat(i) * xStep, y: y)
            if !started { path.move(to: point); started = true }
            else { path.line(to: point) }
        }

        // 描边
        color.set()
        path.lineWidth = offset
        path.stroke()

        // 渐变填充
        let fill = path.copy() as! NSBezierPath
        fill.line(to: CGPoint(x: frame.width, y: 0))
        fill.line(to: CGPoint(x: 0, y: 0))
        fill.close()
        NSGradient(colors: [
            color.withAlphaComponent(0.5),
            color.withAlphaComponent(0.8)
        ])?.draw(in: fill, angle: 90)
    }

    func addValue(_ value: Double) {
        values.removeFirst()
        values.append(value)
        Task { @MainActor in self.display() }
    }
}
```

**关键要点**（来自 Stats 代码分析）：
- 线宽用 `1 / backingScaleFactor` 确保 Retina 下 1 物理像素
- `canDrawConcurrently = true` 允许并发绘制（Stats `Mini.swift:79`）
- 仅在 `window?.isVisible` 时调用 `display()` 避免无意义重绘（Stats `Charts.swift:367-369`）
- 使用 DispatchQueue 保护数据读写的线程安全（Stats 用 DispatchQueue，我们改用 actor 或 @MainActor）

#### Menu Bar 尺寸常量

来自 Stats `Kit/constants.swift` 的经验值：

```swift
enum MenuBarConstants {
    /// 系统 menu bar 高度（动态获取）
    static var height: CGFloat {
        let h = NSApplication.shared.mainMenu?.menuBarHeight ?? 0
        return h == 0 ? 22 : h
    }
    /// Widget 间距
    static let widgetSpacing: CGFloat = 2
    /// Widget 上下内边距
    static let verticalPadding: CGFloat = 2
}
```

### 4.2 StatusItem 管理

Stats 在 `Kit/module/widget.swift:325-353` 中展示了 NSStatusItem 的管理模式。InfoBar 简化为单一 StatusItem：

```swift
@MainActor
class StatusItemManager {
    private var statusItem: NSStatusItem?
    private let containerView = MenuBarContainerView()
    private var popupWindow: PopupWindow?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.addSubview(containerView)
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    func updateLayout() {
        let totalWidth = containerView.recalculateWidth()
        statusItem?.length = totalWidth
    }

    @objc private func handleClick() {
        guard let button = statusItem?.button,
              let window = button.window else { return }
        let origin = window.frame.origin
        let center = window.frame.width / 2
        popupWindow?.toggle(below: origin, center: center)
    }
}
```

### 4.3 弹窗系统

参考 Stats 的 `Kit/module/popup.swift` 和 `Kit/module/module.swift:252-291` 中的定位算法：

#### PopupWindow

```swift
class PopupWindow: NSWindow {
    private var locked = false

    init(contentWidth: CGFloat = 320, contentHeight: CGFloat = 400) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            // Stats 用 [.titled, .fullSizeContentView] 实现无边框但保留圆角
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = .moveToActiveSpace
        delegate = self
    }
}
```

#### 定位算法

Stats 的精确定位逻辑（`module.swift:275-284`）：

```swift
struct PopupPositioner {
    /// 将弹窗定位到 menu bar item 正下方
    static func position(
        popup: NSWindow,
        buttonOrigin: CGPoint,    // menu bar item 窗口的 origin
        buttonCenter: CGFloat     // menu bar item 窗口宽度的一半
    ) {
        guard let contentSize = popup.contentView?.intrinsicContentSize else { return }

        let windowCenter = contentSize.width / 2
        var x = buttonOrigin.x - windowCenter + buttonCenter
        let y = buttonOrigin.y - contentSize.height - 3

        // 防止超出屏幕右边界
        let maxWidth = NSScreen.screens.map { $0.frame.width }.reduce(0, +)
        if x + contentSize.width > maxWidth {
            x = maxWidth - contentSize.width - 3
        }

        popup.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

#### 毛玻璃背景

Stats 的实现（`popup.swift:182-188`）：

```swift
let visualEffect = NSVisualEffectView(frame: bounds)
visualEffect.material = .titlebar      // 与系统标题栏一致的模糊材质
visualEffect.blendingMode = .behindWindow
visualEffect.state = .active
visualEffect.wantsLayer = true
visualEffect.layer?.cornerRadius = 6
```

### 4.4 Swift ↔ JS 通信桥

#### Swift 侧

```swift
import WebKit

class WebViewBridge: NSObject, WKScriptMessageHandler {
    private let webView: WKWebView

    init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        self.webView = WKWebView(frame: frame, configuration: config)
        super.init()

        // 注册 JS → Swift 通道
        config.userContentController.add(self, name: "infobar")
    }

    // JS → Swift
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        handleMessage(type: type, payload: body["payload"])
    }

    // Swift → JS
    func pushData(_ event: String, data: Encodable) {
        guard let json = try? JSONEncoder().encode(data),
              let jsonStr = String(data: json, encoding: .utf8) else { return }
        let js = "window.__infobar__.emit('\(event)', \(jsonStr))"
        Task { @MainActor in
            try? await webView.evaluateJavaScript(js)
        }
    }
}
```

#### JS 侧（React）

```typescript
// bridge.ts
type Listener = (data: unknown) => void;
const listeners = new Map<string, Set<Listener>>();

// Swift 调用入口
window.__infobar__ = {
  emit(event: string, data: unknown) {
    listeners.get(event)?.forEach(fn => fn(data));
  }
};

// React 侧订阅
export function subscribe(event: string, fn: Listener) {
  if (!listeners.has(event)) listeners.set(event, new Set());
  listeners.get(event)!.add(fn);
  return () => listeners.get(event)?.delete(fn);
}

// React 侧发送
export function send(type: string, payload?: unknown) {
  window.webkit.messageHandlers.infobar.postMessage({ type, payload });
}
```

```tsx
// hooks/useNativeData.ts
import { useState, useEffect } from 'react';
import { subscribe } from '../bridge';

export function useNativeData<T>(event: string, initial: T): T {
  const [data, setData] = useState<T>(initial);
  useEffect(() => subscribe(event, (d) => setData(d as T)), [event]);
  return data;
}
```

### 4.5 数据采集层

```swift
/// 数据源协议
protocol DataProvider: AnyObject {
    associatedtype Value: Sendable
    /// 采集间隔（秒）
    var interval: TimeInterval { get }
    /// 单次采集
    func fetch() async throws -> Value
}

/// 定时调度器，驱动数据采集 → widget 更新 → JS 推送
actor DataScheduler {
    private var tasks: [String: Task<Void, Never>] = [:]

    func start<P: DataProvider>(
        id: String,
        provider: P,
        onUpdate: @Sendable @escaping (P.Value) -> Void
    ) {
        tasks[id]?.cancel()
        tasks[id] = Task {
            while !Task.isCancelled {
                if let value = try? await provider.fetch() {
                    onUpdate(value)
                }
                try? await Task.sleep(for: .seconds(provider.interval))
            }
        }
    }

    func stop(id: String) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
    }
}
```

## 5. 数据流

```
┌─────────────┐     async/await     ┌──────────────────┐
│ DataProvider │ ──────────────────► │  DataScheduler   │
│ (采集原始数据) │                     │  (定时调度)       │
└─────────────┘                     └────────┬─────────┘
                                             │
                                             │ onUpdate callback
                                             ▼
                              ┌──────────────────────────┐
                              │      AppState            │
                              │ (@MainActor, Published)  │
                              └─────┬──────────┬─────────┘
                                    │          │
                       ┌────────────┘          └────────────┐
                       ▼                                    ▼
              ┌─────────────────┐                  ┌────────────────┐
              │ Menu Bar Widget │                  │  WebViewBridge │
              │ (.display())   │                  │ (pushData)     │
              └─────────────────┘                  └───────┬────────┘
                                                           │
                                                           ▼
                                                   ┌──────────────┐
                                                   │  React App   │
                                                   │ (WKWebView)  │
                                                   └──────────────┘
```

## 6. React 弹窗应用

### 工程配置

```
react-app/
├── package.json          # React 18+ / Vite
├── vite.config.ts        # base: './' (相对路径，WKWebView 加载本地文件)
├── src/
│   ├── App.tsx
│   ├── bridge.ts         # Swift 通信封装
│   ├── hooks/
│   │   └── useNativeData.ts
│   ├── components/
│   │   ├── charts/       # 图表组件（ECharts / Recharts）
│   │   └── layout/       # 布局组件
│   └── styles/
│       └── global.css    # 透明背景 + 系统字体
└── tsconfig.json
```

### 关键 CSS

```css
/* 让 WebView 背景透明，露出原生毛玻璃 */
html, body {
  background: transparent;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  color-scheme: light dark; /* 跟随系统明暗模式 */
}
```

WKWebView 侧需要配置：

```swift
webView.setValue(false, forKey: "drawsBackground")  // 背景透明
```

### 构建集成

React 应用 build 后的产物复制到 Xcode 的 `Resources/WebApp/` 目录：

```bash
cd react-app && npm run build
# vite 输出到 dist/
cp -r dist/* ../InfoBar/Resources/WebApp/
```

Xcode 中将 `Resources/WebApp` 添加为 folder reference（蓝色文件夹图标），确保整个目录被打包进 app bundle。

Swift 侧加载：

```swift
if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebApp") {
    webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
}
```

## 7. 设置窗口

设置界面用 SwiftUI 实现（不走 WebView），因为它与系统偏好设置风格一致且交互简单：

```swift
@main
struct InfoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // 设置窗口
        Settings {
            SettingsView()
        }
    }
}

// AppDelegate 负责 NSStatusItem 等 AppKit 层
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItemManager = StatusItemManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemManager.setup()
    }
}
```

## 8. 与 Stats 的参考关系

以下是 Stats 代码中值得参考的核心文件和我们的对应模块：

| Stats 源码 | 参考内容 | InfoBar 对应模块 |
|---|---|---|
| `Kit/plugins/Charts.swift` LineChartView.draw() | NSBezierPath 折线绘制、渐变填充、Retina 适配、tooltip | `MenuBar/Widgets/LineChartWidget.swift` |
| `Kit/plugins/Charts.swift` BarChartView.draw() | 柱状图分块绘制 | `MenuBar/Widgets/BarChartWidget.swift` |
| `Kit/Widgets/Mini.swift` draw() | 紧凑数字渲染、颜色分级、标签布局 | `MenuBar/Widgets/MiniWidget.swift` |
| `Kit/module/widget.swift` WidgetWrapper | 基类模式：宽度管理、线程安全重绘、点击事件 | `MenuBar/Widgets/WidgetBase.swift` |
| `Kit/module/widget.swift` SWidget.setMenuBarItem() | NSStatusItem 创建、button 配置、子视图挂载 | `MenuBar/StatusItemManager.swift` |
| `Kit/module/widget.swift` MenuBar / MenuBarView | 多 widget 水平布局和宽度重算 | `MenuBar/MenuBarView.swift` |
| `Kit/module/popup.swift` PopupWindow | NSWindow 样式配置、delegate 行为 | `Popup/PopupWindow.swift` |
| `Kit/module/popup.swift` PopupView | NSVisualEffectView 毛玻璃配置、header + body 布局 | `Popup/PopupViewController.swift` |
| `Kit/module/module.swift` listenForPopupToggle() | 弹窗定位算法（坐标计算 + 屏幕边界） | `Popup/PopupPositioner.swift` |
| `Kit/constants.swift` | Menu bar 高度获取、间距常量 | 内联到各模块 |

**不参考的部分**：
- Stats 的 plist 驱动模块加载机制（过于复杂，InfoBar 不需要插件化）
- Stats 的 NotificationCenter 事件总线（改用 Combine / async streams）
- Stats 的 DispatchQueue 并发模式（改用 Swift Concurrency）
- Stats 的 Store/UserDefaults 封装（改用 @AppStorage）

## 9. 开发路径

### Phase 1 — 骨架

目标：app 启动后在 menu bar 出现一个静态 icon，点击弹出带毛玻璃背景的空浮窗。

- [ ] Xcode 项目初始化（SwiftUI App + NSApplicationDelegateAdaptor）
- [ ] StatusItemManager：创建 NSStatusItem，显示占位图标
- [ ] PopupWindow：NSWindow + NSVisualEffectView，点击 statusItem 弹出/收起
- [ ] PopupPositioner：定位到 statusItem 正下方

### Phase 2 — Menu Bar Widget

目标：menu bar 上能渲染一个实时更新的折线图 widget。

- [ ] WidgetBase 基类
- [ ] LineChartWidget：NSBezierPath 绘制 + 渐变填充
- [ ] MiniWidget：数字百分比显示
- [ ] MenuBarContainerView：多 widget 水平排列 + 动态宽度

### Phase 3 — WebView 弹窗

目标：点击 menu bar 后弹窗里显示 React 渲染的详情页。

- [ ] React 项目初始化（Vite + TypeScript）
- [ ] WKWebView 集成，加载本地 HTML
- [ ] Bridge 层：Swift → JS 推送数据、JS → Swift 回调
- [ ] 基础图表组件（一个 React 图表页面接收数据并渲染）

### Phase 4 — 数据接入

目标：接入真实数据源，打通 数据采集 → widget 更新 → 弹窗详情 的完整链路。

- [ ] DataProvider 协议 + DataScheduler
- [ ] 第一个数据源实现
- [ ] 数据驱动 widget 刷新
- [ ] 数据推送到 React 弹窗

### Phase 5 — 打磨

- [ ] 设置窗口（SwiftUI Settings scene）
- [ ] 点击外部自动关闭弹窗
- [ ] 弹窗拖动后 lock（参考 Stats `popup.swift:89-101`）
- [ ] 明暗模式跟随
- [ ] React 侧 CSS 暗色适配
