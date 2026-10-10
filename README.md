# Codex Inline Stats

Windows 上的 Codex 桌面端内嵌统计栏：在聊天输入框下方显示处理阶段、最近调用均速、累计 token、缓存命中率和整段聊天当前有效上下文的估计占比。

**非官方本机定制。** 使用 localhost 调试连接向页面加入 DOM，未修改 Codex 的签名安装文件。界面占据正常布局空间，随聊天切换重新挂载，不使用悬浮窗口。

## 环境

- Windows 10/11，Windows PowerShell 5.1 或 PowerShell 7。
- 通过 MSIX/Microsoft Store 安装的 Codex。当前验证版本：`26.1002.7124.0`。其他安装布局尚未验证。
- [Node.js](https://nodejs.org/) 22+ 和 [Python](https://www.python.org/downloads/windows/) 3.10+，加入 PATH。只使用标准库，无 npm/pip 依赖。

## 安装与启动

下载 Release 中的 ZIP 或本仓库源码，完整解压，进入该文件夹执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

安装到 `%LOCALAPPDATA%\Programs\CodexInlineStats`，创建桌面入口 **Codex（内置统计）**。从菜单完全退出 Codex，再使用该入口启动；单独关闭窗口可能仍留下后台进程。原有聊天正在执行时，先等待任务结束。

正常使用只需此入口，它会一起启动采集器。原版入口启动的新进程不会启用统计。安装器不会自动退出或重启 Codex。

运行环境未加入 PATH 时，可显式指定路径：

```powershell
.\Install.ps1 -NodePath 'C:\path\to\node.exe' -PythonPath 'C:\path\to\python.exe'
```

可选：`-StartAtLogin` 启用登录后后台采集；它不会启动 Codex。`-Port 9335` 指定本机端口；`-InstallDir` 指定安装目录；`-NoShortcuts` 不创建快捷方式；`-CheckOnly` 只检查环境，不安装。端口冲突时请选择其他端口，并完全退出后从新入口启动。

## 统计口径

| 指标 | 含义与限制 |
| --- | --- |
| 生成中 / 工具运行中 / 最近响应 | 依据日志事件判断的处理阶段，可能有交付延迟。 |
| 调用均速 | 最近已完成响应的输出 token（含推理，不重复相加）÷ 客户端观察到的调用间隔。包含排队、首 token 等待、网络及日志交付开销；从已知工具全部返回后重新计时。不是实时逐 token 速度，也不是服务端解码 TPS。 |
| 累计 token | 日志的累计 token 计数，可能在每次调用中重复包含上下文输入；不代表订阅账单或唯一上下文长度。 |
| 缓存命中 | 最近一次调用的缓存输入 token ÷ 全部输入 token。 |
| 对话上下文约 X% · X / Y tok | 最近上报的 `last_token_usage.total_tokens` ÷ `model_context_window`。反映整段聊天当时仍在使用的有效上下文估计，包含保留历史、指令及工具信息；不是最后一轮输入，也不是所有历史原文的累计 token。窗口取会话报告，不按模型名猜测。 |

没有可靠计时边界时显示 `--`，过旧数据也不显示速度。新一轮尚未完成调用时不沿用上一轮速度。没有硬编码 50 tok/s 上限。

上下文会在下一条 `token_count` 记录到达时更新。压缩、回滚或模型改变后清除旧读数，显示“等待新记录”，然后采用新的窗口和计数。特别是压缩后，日志可能报告输入/输出为 0、但 `total_tokens` 为非零的重新估算值；这里保留该上下文读数。缺少容量或计数时不猜测百分比，上报超过容量时也不悄悄封顶。最近添加的用户/工具内容可能尚未被计入，因此不能保证每一刻精确。Codex 原生 UI 可能采用额外基线调整，百分比不一定相同。

旧算法曾使用最后一条 reasoning/message 的交付时间作为整次响应起点，导致上百甚至上千 tok/s 的虚高读数。此版本修正为完整响应的观察间隔。原始日志缺少完整的服务端时序，因此无法精确还原官方生成 TPS。

## 客户端更新后的维护

1. 正常更新 Codex，完全退出后从 **Codex（内置统计）** 启动。脚本自动发现新版 MSIX 安装路径。
2. 切换两个聊天，确认统计跟随聊天且布局正常；完成一次回复，确认数字更新。
3. 不显示时运行诊断：

```powershell
& "$env:LOCALAPPDATA\Programs\CodexInlineStats\Get-Status.ps1"
```

`debugReachable=false` 通常需要完全退出并从专用入口重开，或检查端口冲突；`codexPageFound=false` 可能是页面地址变更。`active` 只证明最近一次注入/更新成功，不证明所有指标口径正确。结合时间戳检查状态是否过旧。

插件更新：下载新源码，重新执行 `Install.ps1`（自定义路径或端口应使用原参数），再执行安装目录的 `StartAgent.ps1`。更新会停止该目录的采集器，不会中断 Codex 聊天。没有自动更新、自动适配或自动上传诊断。

若客户端改变 DOM、路由或 React 属性，应检查 `renderer.js`，修改后递增 `version`；若改变日志或状态数据库格式，应检查 `telemetry.py` 和 `reader.py`。避免仅根据数值是否“看起来合理”判断兼容性。

## 安全与隐私

采集器读取本机 Codex 状态数据库和会话日志，以绑定当前聊天和提取用量。它没有云端服务，不上传聊天、日志或统计数据，也不读取账号凭据。源码和 Release 不包含开发者本机日志、配置、账号资料或运行环境二进制。

**调试端口意味着本机其他进程也能访问和控制应用页面。** 启动参数限定到 `127.0.0.1`，请勿开放防火墙、代理转发或分享调试连接；实际使用时应检查端口仅监听 loopback。完全退出 Codex 才会关闭它。对调试端口有严格限制的环境不适合使用此方案。

此功能依赖客户端内部结构，不属于稳定官方插件接口。客户端更新可能使统计停止或出现口径变化。

## 停用与卸载

临时停用：运行安装目录中的 `StartAgent.ps1 -StopOnly`，完全退出 Codex，再从原版入口启动。当前已注入的栏位会在页面销毁后消失。

卸载：

```powershell
& "$env:LOCALAPPDATA\Programs\CodexInlineStats\Uninstall.ps1"
```

脚本停止该目录的采集器及 Python reader，移除指向该目录的桌面/登录启动快捷方式。完全退出后从原版入口启动。安装文件保留，可手动删除该目录；不删除 Codex 聊天，不修改 Codex 安装，也不会恢复或启动其他 HUD。

## 开发与验证

```powershell
python tests/test_telemetry.py
node --check agent.mjs
node --check renderer.js
node tests/test-renderer.mjs
.\Install.ps1 -CheckOnly
```

渲染测试使用本机 Edge headless 和合成聊天页面；可通过环境变量 `EDGE_PATH` 指定 Edge 可执行文件。测试包含聊天重新挂载、旧响应拒绝、窄布局、上下文读数与等待状态、字段口径和移除。解析测试覆盖完整响应计时、推理不重复计数、用量去重、并行工具返回、重复通知、边界缺失，以及压缩后上下文重估、模型/窗口变化、回滚和无效记录。

Windows CI 在 Python 3.10 / 3.14 与 Node 22 上运行这些检查。合成页面测试不等于所有真实客户端版本、主题、窗口尺寸和模型的兼容性保证。原型曾通过本机真实日志回放和真实 Codex 内嵌验收；发布版的安装与生命周期脚本另经隔离目录验证，尚无第二台机器实测。

## 许可与来源

MIT。`telemetry.py` 改编自 [drkang7/codex-token-hud](https://github.com/drkang7/codex-token-hud) `v1.2.0-beta.1`，保留上游署名和许可，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
