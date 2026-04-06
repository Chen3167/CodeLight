<div align="center">

# CodeLight

**Your Claude Code sessions, on your iPhone.**

A companion app to [CodeIsland](https://github.com/xmqywx/CodeIsland) — monitor and control your AI coding sessions from anywhere, with Dynamic Island support.

This is a passion project built purely out of personal interest. It is **free and open-source** with no commercial intentions whatsoever. I welcome everyone to try it out, report bugs, and contribute code. Let's build something great together!

这是一个纯粹出于个人兴趣开发的项目，**完全免费开源**，没有任何商业目的。欢迎大家试用、提 Bug、贡献代码。一起把它做得更好！

[![GitHub stars](https://img.shields.io/github/stars/xmqywx/CodeLight?style=social)](https://github.com/xmqywx/CodeLight/stargazers)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![iOS](https://img.shields.io/badge/iOS-17%2B-black?style=flat-square&logo=apple)](https://github.com/xmqywx/CodeLight/releases)

</div>

---

## What is CodeLight?

**CodeIsland** lives in your Mac's notch. **CodeLight** lives in your pocket.

When you step away from your desk, CodeLight keeps you connected to your Claude Code sessions. See what Claude is doing, read the conversation, and send messages — all from your iPhone.

```
  Mac (CodeIsland)              Cloud                    iPhone (CodeLight)
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────────────┐
│  Claude Code     │    │  CodeLight       │    │  📱 Session list         │
│  sessions are    │───▶│  Server          │───▶│  💬 Chat view            │
│  synced in       │    │  (self-hosted)   │    │  🏝️ Dynamic Island      │
│  real-time       │◀───│                  │◀───│  ⌨️ Send messages        │
└──────────────────┘    └──────────────────┘    └──────────────────────────┘
```

## Features

### Real-time Session Sync

See your Claude Code conversations on your iPhone as they happen. Every message, tool call, and thinking block streams to your phone in real-time.

### Dynamic Island

Your iPhone's Dynamic Island becomes a status indicator for Claude Code:

| State | What you see |
|-------|-------------|
| 🟣 Thinking | Project name + elapsed time |
| 🔵 Tool running | Tool name (e.g., "Edit main.swift") |
| 🟠 Needs approval | Tap to open and review |
| 🟢 Done | Auto-dismisses after 5 seconds |

### Send Messages

Type messages to Claude Code from your phone. Switch models (Opus / Sonnet / Haiku) and permission modes without touching your Mac.

### Self-Hosted & Private

Run your own CodeLight Server. Your data stays on your infrastructure. The server is **zero-knowledge** — it relays encrypted messages without reading them.

### QR Code Pairing

No accounts. No passwords. Scan a QR code from CodeIsland to pair your phone with your Mac. Your public key is your identity.

### Multi-Server Support

Connect to multiple CodeLight Servers — monitor sessions across different machines or environments from a single app.

## How It Works

CodeLight extends [CodeIsland](https://github.com/xmqywx/CodeIsland) with remote access:

1. **Claude Code** runs on your Mac and emits hook events
2. **CodeIsland** (Mac notch app) receives hooks and syncs session data to the CodeLight Server
3. **CodeLight Server** (self-hosted) relays encrypted messages via Socket.io
4. **CodeLight** (iPhone app) displays sessions and lets you send messages back

All communication is encrypted end-to-end. The server cannot read your messages.

## Requirements

- [CodeIsland](https://github.com/xmqywx/CodeIsland) installed on your Mac (the bridge between Claude Code and the server)
- A server to host CodeLight Server (any VPS with Node.js 20+ and PostgreSQL)
- iPhone running iOS 17+

## Quick Start

### 1. Deploy the Server

```bash
git clone https://github.com/xmqywx/CodeLight.git
cd CodeLight/server
npm install

# Configure
cp .env.example .env
# Set DATABASE_URL, MASTER_SECRET (random 64-char hex), and PORT

# Database setup
npx dotenv -e .env -- prisma migrate dev --name init

# Run
npm start
```

Set up a reverse proxy (Nginx) with SSL for production. See [Server Configuration](#server-configuration) for details.

### 2. Build the iPhone App

```bash
cd CodeLight/app
open CodeLight.xcodeproj
```

- Select your development team for both targets
- Connect your iPhone, press **⌘R**
- Enter your server URL on first launch

### 3. Connect CodeIsland

CodeIsland's sync module connects your Mac to the server automatically. On the `feature/codelight-sync` branch, CodeIsland will:

- Authenticate with the server on launch
- Sync all active Claude Code sessions
- Relay messages in real-time

## Project Structure

```
CodeLight/
├── server/              # Relay server (Fastify + Socket.io + PostgreSQL)
├── app/                 # iPhone app (SwiftUI + ActivityKit)
│   ├── CodeLight/       # Main app target
│   └── CodeLightWidget/ # Dynamic Island widget extension
├── packages/            # Shared Swift Packages
│   ├── CodeLightProtocol/   # Message types
│   ├── CodeLightCrypto/     # E2E encryption (CryptoKit)
│   └── CodeLightSocket/     # Socket.io client wrapper
└── DESIGN.md            # Full design specification
```

## Server Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `MASTER_SECRET` | Yes | Random hex string for JWT signing |
| `PORT` | No | Server port (default: 3006) |
| `APNS_KEY_ID` | No | Apple Push Notification key ID |
| `APNS_TEAM_ID` | No | Apple Developer Team ID |
| `APNS_KEY` | No | Base64-encoded .p8 private key |
| `APNS_BUNDLE_ID` | No | App bundle ID for push |

### Nginx Example

```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3006;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400s;
        proxy_buffering off;
    }
}
```

## Security

| Layer | How |
|-------|-----|
| **Identity** | Ed25519 public key — no accounts, no passwords |
| **Transport** | TLS (HTTPS/WSS) |
| **Messages** | E2E encryption ready (ChaChaPoly via CryptoKit) |
| **Server** | Zero-knowledge relay — stores only ciphertext |
| **Keys** | Stored in iOS/macOS Keychain, never exported |

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Server | Node.js, TypeScript, Fastify 5, Socket.io, Prisma, PostgreSQL |
| iOS App | Swift, SwiftUI, ActivityKit, WidgetKit |
| Encryption | Apple CryptoKit (ChaChaPoly, Curve25519) |
| Mac Bridge | [CodeIsland](https://github.com/xmqywx/CodeIsland) + Socket.io Swift |

## Engineering Highlights / 精巧设计

A handful of non-obvious design decisions that make the system feel solid in practice.

### 1. Rock-solid phone → terminal routing

Phone messages have to land in the **exact** Claude Code terminal that the user picked — not "the first active Claude window I could find". Naive approaches (workspace title fuzzy-matching, `cwd` substring) fall apart the moment you have multiple sessions in `/Users/ying` or restart a session.

The real fix uses two facts the system already knows:

1. Claude Code CLI is invoked with `--session-id <UUID>` on argv — visible via `ps -Ax`.
2. cmux automatically exports `CMUX_WORKSPACE_ID` and `CMUX_SURFACE_ID` into every pane it spawns — readable via `ps -E -p <pid>`.

So the server includes the session tag (Claude UUID) in its broadcast, and CodeIsland does:

```
ps -Ax | grep "claude --session-id <UUID>"         →  PID
ps -E  -p <PID>                                    →  CMUX_WORKSPACE_ID, CMUX_SURFACE_ID
cmux send --workspace <ws> --surface <surf> -- …   →  exact pane, zero guesses
```

No title matching, no cwd heuristics. If the PID doesn't exist the message is cleanly dropped — orphan server sessions never silently hijack the wrong window.

手机发来的消息必须精确落到用户选中的那个 Claude 终端。传统做法（workspace 标题模糊匹配、`cwd` 子串）在多 session、同一目录、session 重启之后全部崩。真正靠谱的路径是：Claude CLI 的 `--session-id <UUID>` 就写在 argv 里（`ps -Ax` 可见），cmux 又自动把 `CMUX_WORKSPACE_ID` / `CMUX_SURFACE_ID` 注入每个 pane 的环境变量（`ps -E -p <pid>` 可读）。两个事实一拼接，就能从"session UUID"零猜测地定位到"cmux 的哪个 surface"，找不到就直接 drop。

### 2. One global Live Activity, not one per session

Starting a Live Activity per Claude session made the iPhone Dynamic Island stretch and collapse awkwardly as sessions came and went. Worse, iOS caps concurrent Live Activities hard.

Instead CodeLight runs **a single global activity** that represents "whatever Claude is doing right now, anywhere". The activity's `ContentState` carries `activeSessionId`, `activeSessions`, `totalSessions`, and the latest phase — and whichever session had the most recent phase change wins the Dynamic Island. Switching context is just a state update, not a create/destroy cycle.

早期的每 session 一个 Live Activity 会让灵动岛频繁伸缩，而且 iOS 对并发 Live Activity 数量有上限。改成**一个全局 Activity**，ContentState 里记当前活跃 session、总数和最新 phase，谁最近有事件发生就把灵动岛让给谁，切换只是一次 state update。

### 3. Phase messages as the Live Activity pulse

CodeLight's Live Activity only updates on `type: "phase"` messages — a tiny heartbeat CodeIsland emits whenever Claude transitions (`thinking → tool_running → waiting_approval → …`). Regular chat messages don't trigger re-renders. This keeps APNs push volume low enough to stay under Apple's budget and the Dynamic Island stops flickering when Claude writes a long assistant reply.

灵动岛只响应 `type: "phase"` 这种心跳消息（由 CodeIsland 在状态迁移时发出），普通对话消息不触发更新。这样既能控住 APNs 推送频率（苹果有预算上限），又避免 Claude 输出长回答时灵动岛疯狂抖动。

### 4. HTTP/2 is mandatory for APNs Live Activity pushes

Node's built-in `fetch()` uses HTTP/1.1 and **fails** against `api.push.apple.com` with `TypeError: fetch failed` — no clean error, just a dead request. The server hand-rolls HTTP/2 requests via `node:http2` for Live Activity updates. Regular APNs alerts keep using `fetch()` because Apple accepts both for that path; only Live Activity demands HTTP/2.

Node 自带的 `fetch()` 走 HTTP/1.1，打 `api.push.apple.com` 会直接 `TypeError: fetch failed`，连个清晰报错都没有。服务器用 `node:http2` 手搓 HTTP/2 请求处理 Live Activity 推送。普通 APNs alert 还能用 `fetch()`，只有 Live Activity 这条路强制 HTTP/2。

### 5. Phone-injection dedup ring

Round-trip: phone sends text → server → CodeIsland pastes into cmux → Claude writes it to its JSONL → CodeIsland's file watcher sees a "new user message" → ships it back to the server → phone gets **a second copy** of what it just sent.

CodeIsland keeps a 60-second TTL ring `(claudeUuid, text) → injectedAt`. When MessageRelay is about to ship a user message to the server, it consumes a matching entry and skips. Echo loop broken, no localId negotiation, no server changes.

手机发 → 服务器 → CodeIsland 粘贴到 cmux → Claude 写进 JSONL → CodeIsland 监听到"新用户消息" → 回传服务器 → 手机收到自己刚发的消息的副本。解法是 CodeIsland 保留一个 60 秒 TTL 的 `(claudeUuid, text)` 去重环，MessageRelay 在上传前消费一次匹配项直接跳过。不需要改服务器，不需要协商 localId。

### 6. Ephemeral blob store for image uploads

Images from the phone are transit cargo, not chat history — the real source of truth is Claude's own JSONL once the image is pasted. So the server's blob store is **deliberately in-memory + disk**, never in the DB:

- `POST /v1/blobs` writes to `./blobs/<id>.bin`, metadata lives in a `Map`
- Three-tier cleanup: `blob-consumed` socket ack deletes on first successful CodeIsland pickup; a 10-minute TTL sweeper catches the rest; server startup purges the entire `blobs/` directory on every boot
- No Prisma model, no migrations, no orphan rows — a server restart is a clean slate by design

手机发过来的图片只是**过境数据**，真正的历史在 Claude 自己的 JSONL 里（粘贴后被 Claude 记录）。所以服务器的 blob 存储刻意做成**内存 Map + 磁盘文件**，完全不进数据库：上传即落盘，`blob-consumed` socket ack 一到就删，10 分钟 TTL 兜底，启动时整个 `blobs/` 目录清空。没有 prisma 模型、没有迁移、没有孤儿行——每次重启都是干净状态。

### 7. Image paste without a paste API

cmux has no "paste image" command. Its CLI only speaks text and key events. But manually pressing Cmd+V in a cmux terminal with an image on the clipboard makes Claude see `[Image #N]` — so the paste pipeline exists, it just needs the macOS UI layer.

CodeIsland's pipeline:

1. Download the blob over HTTPS
2. `cmux focus-panel --panel <surfaceId> --workspace <wsId>` — switch cmux's internal view
3. AppleScript `tell application id "com.cmuxterm.app" to activate` + poll `NSWorkspace.frontmostApplication` until cmux is truly frontmost (up to 1 s)
4. Write the image to `NSPasteboard` in NSImage, `public.jpeg`, and `.tiff` formats all at once for max terminal compatibility
5. AppleScript `tell System Events to keystroke "v" using {command down}` (with a `CGEvent` fallback)
6. `cmux send` for trailing text + Enter

All of this requires **Accessibility permission**, and the permission is tracked by the app's signed path — which means a Debug build in DerivedData is a *different* app from the one in `/Applications`. CodeIsland ships itself to `/Applications/Code Island.app` so the Accessibility grant actually sticks across rebuilds.

cmux 没有粘图 API，但手动 Cmd+V 能让 Claude 认到 `[Image #N]`，所以链路是存在的，只差 macOS UI 层的事件。CodeIsland 的流程：下载 blob → `cmux focus-panel` 切内部视图 → AppleScript `activate` 并轮询 `NSWorkspace.frontmostApplication` 确认 cmux 真的上前台 → `NSPasteboard` 同时写 NSImage / `public.jpeg` / `.tiff` 三种格式最大化兼容 → `System Events` keystroke `v using command down`（`CGEvent` fallback）→ 再 `cmux send` 补正文和回车。这一切需要辅助功能权限，而权限是按签名路径记录的——DerivedData 里的 Debug 和 `/Applications` 里的同名 app 在系统看来是**两个 app**。所以 CodeIsland 每次 rebuild 都会自安装到 `/Applications/Code Island.app`，权限才不会每次都掉。

### 8. Last-message time, not heartbeat time

Session rows used to show `lastActiveAt` — but that field gets bumped every 2 seconds by the `session-alive` heartbeat, so every session in the list showed the same "just now" forever and the timer was meaningless.

The phone now tracks `lastMessageTimeBySession` locally, advancing it only when a real `user`/`assistant` message arrives (phase updates and heartbeats don't count). If nothing has arrived yet in this app session, no time is shown at all — less information is more honest than fake information.

会话列表里的时间原本走 `lastActiveAt`，但它每 2 秒被 `session-alive` 心跳刷新，导致所有 session 显示一样的"刚刚"——一点信息量都没有。现在手机本地维护 `lastMessageTimeBySession`，只有真正的 `user`/`assistant` 消息到达才推进时间（phase 更新和心跳不算），没收到任何消息的会话干脆不显示时间。宁可缺省，也不骗人。

## Roadmap

- [ ] QR code camera scanning (currently manual URL entry)
- [ ] Permission approval from phone
- [ ] Rich message rendering (markdown, code blocks)
- [ ] APNs push notifications for background alerts
- [ ] Tool result visualization
- [ ] Chat history search

## Related Projects

| Project | Description |
|---------|-------------|
| [CodeIsland](https://github.com/xmqywx/CodeIsland) | macOS notch companion for Claude Code — **required** for CodeLight to work |
| [cmux](https://cmux.io) | Modern terminal multiplexer — recommended for multi-session management |

## Contributing

Contributions are welcome!

1. **Report bugs** — [Open an issue](https://github.com/xmqywx/CodeLight/issues)
2. **Submit a PR** — Fork, branch, code, PR
3. **Suggest features** — Open an issue tagged `enhancement`

## 参与贡献

欢迎参与！

1. **提交 Bug** — 在 [Issues](https://github.com/xmqywx/CodeLight/issues) 中描述问题
2. **提交 PR** — Fork 本仓库，新建分支，修改后提交 Pull Request
3. **建议功能** — 在 Issues 中提出

## Contact / 联系方式

- **Email**: xmqywx@gmail.com

## License

MIT — free for any use.
