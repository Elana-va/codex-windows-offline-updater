# Codex Windows 离线更新与模型目录修复工具

[English](README.en.md) | 简体中文

面向无法正常使用 Microsoft Store、需要离线 MSIX 包，或更新 Codex 后仍看不到新模型的 Windows 用户。

这个项目把从 2026 年 7 月开始多次真实使用的更新流程整理成可审计脚本：从微软服务解析 Codex 安装包，下载原始 MSIX，校验签名、发布者、架构和 SHA-256，安装更新，并可选修复过期的本地模型目录覆盖。

> 本项目不是 OpenAI 或 Microsoft 官方项目，也不能绕过账号资格、地区限制、服务端灰度或订阅限制。

想了解它如何从一次真实故障演变成完整工具，请阅读 [开发历程：从无法使用 Microsoft Store 到可审计更新器](docs/development-history.md)。

## 它解决什么

- Microsoft Store 无法打开、无法更新或系统没有可用的商店环境。
- 网页下载到的只是约 1 MB 的 Store 引导程序，而不是完整安装包。
- Codex Desktop 已更新，但模型选择器仍缺少新模型。
- 过去为了提前使用某些模型配置过 `model_catalog_json`，后来这个静态目录阻止新模型出现。
- 需要把官方签名 MSIX 和依赖复制到另一台 Windows 电脑离线安装。

## 安全原则

脚本不会从网盘、第三方镜像或随机论坛下载安装包。下载链路限定为：

1. Microsoft Display Catalog：解析产品和包类别。
2. Microsoft FE3：获取当前包元数据。
3. `*.delivery.mp.microsoft.com`：下载微软分发的原始包。
4. Windows Authenticode：要求签名状态为 `Valid`。
5. `AppxManifest.xml`：要求包名为 `OpenAI.Codex`，架构匹配，签名者与清单发布者一致。
6. SHA-256：记录每个下载文件的摘要，便于复核和传输校验。

安装包不会被解包、修改、重打包或重新签名。本项目不收集遥测，也不会上传你的配置、项目或账号信息。

## 快速开始

要求：Windows 10/11、Windows PowerShell 5.1 或 PowerShell 7、可访问微软分发服务。

```powershell
git clone https://github.com/Elana-va/codex-windows-offline-updater.git
cd codex-windows-offline-updater
```

先诊断，不做修改：

```powershell
powershell -NoProfile -File .\scripts\Get-CodexDiagnostics.ps1
```

下载、验证并安装更新：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

同时修复过期模型目录，并在 15 秒后自动重启 Codex：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 `
  -FixStaleModelCatalog -RestartCodex
```

运行前建议阅读脚本。不要把不明来源的 `irm ... | iex` 命令直接粘贴到管理员终端。

## 参数

| 参数 | 作用 |
|---|---|
| `-DownloadOnly` | 只下载和验证，不安装 |
| `-FixStaleModelCatalog` | 备份 `config.toml`，移除 `model_catalog_json` 覆盖；不删除目录 JSON 文件 |
| `-RestartCodex` | Codex 正在运行时，安排独立进程完成安装并重启应用 |
| `-ForceDownload` | 覆盖同名下载文件并重新获取 |

默认把下载结果放到 `D:\CodexUpdate\<日期>`；没有 D 盘时使用用户下载目录。也可以直接调用主脚本并指定目录：

```powershell
.\scripts\Update-CodexWindows.ps1 -OutputDirectory 'E:\CodexOffline'
```

## 完整工作流

### 1. 诊断当前状态

`Get-CodexDiagnostics.ps1` 会报告 Windows 商店包版本、CLI 版本与路径、模型目录覆盖、Astra 条目和当前相关进程。诊断不会调用模型，也不会消耗 Codex 额度。

### 2. 获取完整官方包

Codex 的 Microsoft Store 产品 ID 是 `9PLM9XGG6VKS`。下载器通过微软目录和 FE3 服务解析当前 x64 或 arm64 包，然后仅接受微软 Delivery Optimization CDN 返回的文件。

输出目录包含原始安装包、记录来源与哈希的 `package-manifest.json`，以及可随目录复制到另一台电脑使用的 `install.ps1`。

### 3. 独立验证

外层更新器不会只相信下载器的结果，它会再次检查 Authenticode、`OpenAI.Codex` 包身份、CPU 架构、签名证书与 Publisher 是否一致，并重新计算 SHA-256。

### 4. 处理正在运行的 Codex

当 Codex 正在占用旧版本时，脚本先使用 `DeferRegistrationWhenPackagesAreInUse` 暂存新包。

- 未使用 `-RestartCodex`：完全退出 Codex 后手动重新打开。
- 使用 `-RestartCodex`：生成本地辅助脚本，15 秒后完成注册并重新打开 Codex。

辅助脚本和日志保存在输出目录，便于审计。它通过 Windows 包部署关闭正在使用旧包的应用，不会按名称终止所有 `codex.exe`，避免误伤其他项目中的 CLI。

## 更新成功但没有新模型

客户端版本、模型目录和账号资格是三层不同状态。

### 常见原因：旧的 `model_catalog_json`

一些早期教程会在 `%USERPROFILE%\.codex\config.toml` 中加入：

```toml
model_catalog_json = 'C:\Users\you\.codex\some-old-model-catalog.json'
```

这会让 Codex 使用静态本地目录。客户端即使更新成功，新模型也可能被旧 JSON 隐藏。

```powershell
# 先诊断
.\scripts\Get-CodexDiagnostics.ps1

# 确认后修复
.\scripts\Fix-StaleModelCatalog.ps1
```

修复脚本先备份 `config.toml`，只删除配置中的覆盖行，不删除原来的 JSON。随后必须完全退出 Codex、重新打开，并新建任务检查模型选择器。

### Windows 与 Unix 的区别

社区中常见的 `codex app-server daemon restart` 当前只支持 Unix。Windows 用户需要完全退出 Codex Desktop，让旧后台进程结束，然后重新打开。

### 仍然没有模型怎么办

如果应用与 CLI 已更新、没有目录覆盖、已经完全重启并新建任务，但模型仍不可见，问题更可能属于服务端账号资格或灰度。不要下载来历不明的“解锁包”，也不要伪造模型目录；等待服务端开放，或向 OpenAI 支持提交订阅类型、应用版本、平台和问题截图。

## 离线迁移

在可联网电脑上运行：

```powershell
.\install.ps1 -DownloadOnly
```

把整个 `packages` 目录复制到目标电脑，保持安装包、依赖、`package-manifest.json` 和生成的 `install.ps1` 在一起，再运行目录中的 `install.ps1`。部分 Store 产品仍可能要求账号授权或许可证。

## 回滚与备份

- 模型目录修复前的配置位于输出目录的 `config-backups` 中。
- 恢复配置时，完全退出 Codex，再把备份复制回 `%USERPROFILE%\.codex\config.toml`。
- 更新器不会删除旧 MSIX。建议至少保留一个已验证版本，确认新版本稳定后再清理。
- Windows 应用降级比升级风险高，本项目暂不自动执行降级。

## 项目来源

微软 FE3 请求模板和设备令牌处理来自 [StoreDev/StoreLib](https://github.com/StoreDev/StoreLib)。基础下载逻辑改编自 [hanyu1212/microsoft-store-package-downloader-skill](https://github.com/hanyu1212/microsoft-store-package-downloader-skill)，并修复了 PowerShell 对多值 `Content-Length` 响应头的兼容问题。

相关衍生文件按 Mozilla Public License 2.0 开源，详见 [LICENSE](LICENSE)、[NOTICE](NOTICE) 和 [UPSTREAM.md](UPSTREAM.md)。

## 免责声明

本项目使用微软未公开保证长期稳定的 Store/FE3 接口，微软可能随时调整协议。请优先使用 Microsoft Store 的正常更新渠道；当正常渠道不可用时，再把本项目作为可审计的恢复方案。
