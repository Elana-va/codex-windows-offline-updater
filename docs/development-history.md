# 开发历程：从一台无法使用 Microsoft Store 的电脑到可审计的 Codex 更新器

这份记录还原 Codex Windows Offline Updater 的真实形成过程。它不是为了重新发明一个安装器，而是把一次持续数月、跨越安装、更新、模型目录和 Windows 进程占用的排障，整理成其他人也能复现的安全流程。

## 起点：电脑无法走正常商店安装

最初的问题很普通：一台 Windows 电脑缺少正常使用 Microsoft Store 的环境，Codex 又需要更新。网页提供的安装器只是一个很小的 Store 引导程序，执行后仍然依赖本机商店和 Windows 更新组件，无法解决根本问题。

当时确定了三个候选方案：修复本机 Store、从另一台正常电脑准备离线包、直接获取微软分发的完整 MSIX。考虑到系统环境不完整，最终选择第三条路线。

这条路线从一开始就有明确边界：

```text
确认官方产品 ID → 解析微软目录 → 获取原始 MSIX
→ 验证签名与包身份 → 暂存更新 → 退出旧进程 → 完成注册
```

不使用网盘安装包，不绕过证书检查，也不修改或重新封装微软提供的文件。

## 2026 年 7 月：第一次绕开失效的 Store 更新

第一次更新使用 Microsoft Store 产品 ID `9PLM9XGG6VKS`，通过 Store 链接生成服务找到微软 Delivery Optimization CDN 上的完整 x64 MSIX，再使用 `Add-AppxPackage` 安装。

这一阶段证明了两件事：Codex Windows 客户端确实可以在不依赖本机 Store UI 的情况下安装；真正值得信任的不是链接生成网站，而是最终文件是否来自微软分发域名、是否保留有效的 Windows 签名，以及 MSIX 清单中的包身份是否正确。

因此，后续流程不再把“成功下载”当成完成，而是固定加入：

- `Get-AuthenticodeSignature` 必须返回 `Valid`；
- `AppxManifest.xml` 中的 Name 必须是 `OpenAI.Codex`；
- CPU 架构必须与目标电脑匹配；
- 签名证书主题必须与清单 Publisher 一致；
- 保存 SHA-256，便于传输后再次核对。

## 2026 年 8 月：为了新模型固定了实验目录

8 月初，为了在 Codex 中使用当时尚未稳定进入默认目录的 Sol 和 Luna，配置文件加入了一个本地模型目录覆盖：

```toml
model_catalog_json = 'C:\Users\you\.codex\model-catalog-sol-luna-v2-experiment.json'
```

它在当时解决了问题，却埋下了时间延迟型故障。静态 JSON 不会随着服务端模型目录自动演进；只要这行配置仍然存在，未来加入的新模型就可能永远不出现在模型选择器里。

当时并没有立刻发现这个风险，因为应用更新、CLI 更新和已有模型都能正常工作。

## 2026-09-10：为 GPT-6 Astra 再次更新

9 月 10 日，GPT-6 Astra 已出现在官方模型文档中，同事的电脑也能看到新模型，但目标电脑的 Codex 仍然没有。

第一反应是客户端版本落后。检查后发现：

- 已安装 Windows 包：`26.901.6511.0`；
- Microsoft Display Catalog 当前 x64 包：`26.903.8094.0`；
- Codex CLI：`0.153.4`。

这说明 CLI 已经是当前版本，但桌面应用仍需更新。

### 链接生成服务失效

我们先尝试沿用之前的 Store 链接生成页面。页面能够打开，提交产品 ID 后却不再返回文件列表，直接请求接口也受到反爬限制。

与其更换另一个不透明的下载站，我们改为直接调用微软 Display Catalog 和 FE3 更新服务。基础协议实现采用 StoreDev/StoreLib，并参考了社区的 Microsoft Store Package Downloader Skill。

### 下载器在本机暴露兼容问题

微软成功返回了包，但脚本在读取 `Content-Length` 时失败：当前 PowerShell 把响应头表示成 `System.String[]`，原实现却直接转换为 `Int64`。

失败信息是：

```text
Cannot convert the "System.String[]" value of type "System.String[]"
to type "System.Int64".
```

最终将读取逻辑改为明确取得第一个响应头值，再转换成整数。这是一个很小的修改，却决定了流程能不能在不同 PowerShell 网络栈下稳定运行。

### 完整包下载与双重验证

修复后，工具从 `tlu.dl.delivery.mp.microsoft.com` 下载了完整 x64 MSIX：

```text
文件：OpenAI.Codex_26.903.8094.0_x64__2p2nqsd0c76g0.Msix
大小：769,792,128 bytes
版本：26.903.8094.0
签名：Valid
SHA-256：F8A845DD58F177FBCD71B01C7831D742FC90855E4B207EE2D8CE3AB5F9BCC30F
```

下载器验证一次，外层更新流程又独立读取 MSIX 清单并验证一次。第二次验证不是为了形式完整，而是避免上游下载脚本本身出现选择错误或未来被修改后直接影响安装。

### 正在运行的 Codex 无法立即替换

安装时，旧版 Codex 有多个 `ChatGPT.exe` 进程正在使用包文件。直接强制更新会让当前任务突然中断。

处理方式是先使用 `DeferRegistrationWhenPackagesAreInUse` 暂存新包，再启动独立的隐藏 PowerShell 辅助进程。辅助进程等待当前回复完成，要求 Windows 关闭使用旧包的应用，注册新包并重新打开 Codex。

更新完成后，系统报告：

```text
OpenAI.Codex 26.903.8094.0 x64
Status: Ok
```

## 最大转折：版本更新成功，Astra 仍然没有出现

客户端更新已经成功，但模型选择器依然没有 GPT-6 Astra。这证明“没有新模型”等于“客户端太旧”的假设并不完整。

我们把问题拆成三层：

1. **客户端能力**：当前应用和 CLI 是否认识该模型；
2. **模型目录**：客户端实际读取的是服务端目录，还是过去固定的本地 JSON；
3. **账号资格**：OpenAI 是否已经为这个账号和产品入口开放模型。

社区中有 Pro 用户报告类似现象：CLI 已更新，但旧后台或自定义模型目录仍让选择器使用过时数据。Windows 又不支持社区常用的 `codex app-server daemon restart` 生命周期命令，因此必须从配置和实际进程入手。

只读检查很快给出直接证据：

```text
config.toml 第 4 行：
model_catalog_json = '...model-catalog-sol-luna-v2-experiment.json'

目录文件创建于：2026-08-01
目录中包含 gpt-6-astra：否
```

根因不是新版本安装失败，也不是 Pro 订阅失效，而是 8 月实验留下的静态目录覆盖。

## 修复原则：移除覆盖，不删除历史文件

修复前先把 `config.toml` 备份到 D 盘，然后只删除 `model_catalog_json` 这一行。原来的实验 JSON 被保留，默认模型、推理强度、插件和其他设置均不修改。

完全退出并重新打开 Codex 后，新任务重新读取当前模型目录。这个过程随后被整理为 `Fix-StaleModelCatalog.ps1`：

- 没有覆盖时不做修改；
- 目录已经包含 Astra 时默认拒绝误删；
- 修改前自动备份；
- 只删除配置引用，不删除目录文件；
- 修改后再次验证覆盖确实消失。

## 从一次排障变成公开工具

问题解决后，我们没有只保留几条机器专用命令，而是把流程拆成四个可复用部分：

### 1. 只读诊断

`Get-CodexDiagnostics.ps1` 检查 Windows 包、CLI、配置覆盖、目录内容和运行进程，不调用模型，也不消耗 Codex 额度。

### 2. 官方包下载

`download-store-package.ps1` 负责解析微软目录与 FE3，只接受微软 Delivery Optimization 域名返回的包，并记录来源、签名和哈希。

### 3. 独立验证与安装

`Update-CodexWindows.ps1` 再次校验包身份和签名，处理应用占用，并支持只下载、指定输出目录和自动重启。

### 4. 可逆配置修复

`Fix-StaleModelCatalog.ps1` 处理更新成功但新模型仍不可见的常见本地原因，同时明确不承诺绕过服务端账号资格。

仓库最终补充了中英文 README、MPL-2.0 上游说明、安全策略、贡献指南、变更日志、Codex Skill 和 Windows GitHub Actions。

## 我们学到的东西

### 最新客户端不等于最新模型目录

应用版本、CLI、后台进程、本地目录和账号资格必须分别验证。只反复重装客户端，可能永远触碰不到真正原因。

### 临时实验配置需要退出策略

任何为了提前启用能力而加入的静态覆盖，都应该记录用途、创建日期和删除条件。能解决今天问题的配置，也可能阻止明天的正常升级。

### 下载来源和文件身份是两种证据

微软 CDN 地址很重要，但还不够。签名、Publisher、MSIX Identity、架构和哈希共同构成更完整的信任链。

### Windows 更新必须考虑进程占用

在应用内部更新应用本身，需要把下载、暂存、退出和重新注册拆开。独立辅助进程和落盘日志，让更新失败后仍有线索可查。

### 工具应该修复本地状态，而不是伪造权限

项目可以修复旧目录、旧进程和旧客户端，但不能制造 OpenAI 服务端没有授予的模型资格。这条边界既是安全要求，也是排障结论可信的前提。

## 下一步

后续优先级是提高错误分类、补充更多 Windows 版本验证、减少对微软未公开 FE3 行为的耦合，并在不降低签名与身份检查的前提下改善断点续传。

项目主页、安装方式和安全边界见 [README](../README.md)。
