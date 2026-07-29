# GenericAgent Mobile 📱 — AI 助手移动客户端

> Telegram 风格聊天界面 · 多模式 · 语音输入 · 后台通知  
> 后端对接：[SelfAsst](https://github.com/simon/selftast) 服务器

---

## ✨ 功能特性

| 特性 | 说明 |
|:-----|:------|
| 💬 **双模式聊天** | 个人助手 / 编程助手，独立保存对话历史 |
| 🔄 **实时消息** | WebSocket 推送 + 轮询双通道，消息不丢失 |
| 📡 **SSE 流式响应** | AI 回复实时逐字显示，附带处理进度步骤 |
| 🔔 **后台通知** | 息屏时收到新消息推送，前台服务保活 |
| 🎤 **语音输入** | 集成语音转文字，说话即输入 |
| 📝 **Markdown 渲染** | AI 回复带代码高亮、表格、列表等富文本 |
| 💾 **本地缓存** | SQLite 离线存储消息历史，断网不丢 |
| ⚙️ **可配置模型** | 支持 OpenAI / Anthropic / Azure / Ollama / Google / 自定义 |
| 📱 **多平台** | Android · iOS · macOS · Linux · Web |

---

## 🚀 快速开始

### 开发环境

```bash
# 安装 Flutter SDK (>=3.12)
# https://docs.flutter.dev/get-started/install

# 克隆项目
cd SelfAsst-android

# 获取依赖
flutter pub get

# 运行
flutter run
```

### 初始化配置

1. 启动应用，进入 **设置** 页面
2. 配置 **服务器地址**（默认 `http://10.10.10.200:8001`）
3. 输入 **API Token**（与 SelfAsst 服务器一致）
4. 选择 **LLM 提供商** 和 **模型**
5. 点击 **保存** 即可开始聊天

---

## 🏗️ 项目结构

```
lib/
├── main.dart                      # 应用入口 + 通知初始化
├── models/
│   └── message.dart               # 消息数据模型
├── screens/
│   ├── chat_screen.dart           # 聊天主界面（830行）
│   └── settings_screen.dart       # 设置页面（310行）
├── services/
│   ├── api_service.dart           # HTTP/WebSocket/SSE 通信服务
│   ├── background_poller.dart     # 后台轮询新消息
│   ├── background_service.dart    # 前台服务保活
│   └── message_store.dart         # SQLite 本地存储
└── widgets/
    └── message_bubble.dart        # 消息气泡组件（Markdown渲染）
```

---

## 🔧 技术栈

| 技术 | 用途 |
|:-----|:------|
| Flutter / Dart 3.12 | 跨平台 UI 框架 |
| http | REST API 通信 |
| web_socket_channel | WebSocket 实时推送 |
| sqflite | 本地 SQLite 数据库 |
| shared_preferences | 配置持久化 |
| flutter_markdown | Markdown 富文本渲染 |
| speech_to_text | 语音输入 |
| flutter_local_notifications | 本地推送通知 |
| flutter_background_service | 后台保活 |

---

## 📡 API 接口

| 接口 | 说明 |
|:-----|:------|
| `GET /v1/ping` | 健康检查 |
| `POST /v1/chat` | 发送消息 |
| `GET /v1/chat/{msgId}` | 轮询回复状态 |
| `POST /v1/chat/stream` | SSE 流式回复 |
| `GET /v1/history` | 获取历史消息 |
| `POST /v1/llm/configure` | 下发 LLM 配置 |
| `POST /v1/skill/save` | 保存技能 |
| `WebSocket /ws` | 实时消息推送 |

---

## 📄 许可

MIT License