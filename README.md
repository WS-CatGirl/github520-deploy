# GitHub520 Scripts for Linux

本仓库包含一个统一安装入口 `install.sh`、一个引导脚本 `bootstrap.sh`、两个 GitHub520 hosts 管理入口，以及它们共享的 `lib/` 实现：

| 文件 | 用途 | CLI |
|---|---|---|
| **bootstrap.sh** | 引导入口：检查环境、选择仓库源、clone 后调用 `install.sh` | — |
| **askpass.sh** | Gitee HTTPS token 辅助脚本；bootstrap 也会生成临时副本 | — |
| **install.sh** | 统一安装入口，自动选择并拉起对应脚本 | — |
| **Github520-Arch.sh** | Arch Linux 薄入口（`ID=arch`） | `github520-arch` |
| **github520-deploy.sh** | 通用 Linux 薄入口（非 Arch，systemd） | `github520-deploy` |
| **lib/github520-common.sh** | 模块加载器；所有实现都在其余 `lib/*.sh` 中 | — |
| **lib/core.sh** | 全局状态、输出、trap、权限、系统检查和终端辅助 | — |
| **lib/snapshots.sh** | Btrfs / snapper 快照检测与创建 | — |
| **lib/network.sh** | 网络后端检测、静态 IPv4/DNS、验证和回滚 | — |
| **lib/ssh.sh** | SSH 会话/祖先进程检测和红色安全警告 | — |
| **lib/hosts.sh** | GitHub520 下载、校验、hosts 生成、备份和原子写入 | — |
| **lib/systemd.sh** | 安装 CLI/模块副本、service 与 timer | — |
| **lib/uninstall.sh** | hosts 恢复、卸载、彻底清理、状态和日志 | — |
| **lib/installer.sh** | 安装流程、更新模式和最终摘要 | — |
| **lib/cli.sh** | 参数解析、安装来源保护和命令分发 | — |
| **lib/platform-arch.sh** | Arch 平台差异：发行版检查和网络优先级 | — |
| **lib/platform-generic.sh** | 通用平台差异；当前继承 common 的默认实现 | — |

两个入口现在都是薄壳：`Github520-Arch.sh` / `github520-deploy.sh` 只负责选择平台、加载共享库并调用 `main`。`lib/github520-common.sh` 依次加载 `core.sh`、`snapshots.sh`、`network.sh`、`ssh.sh`、`hosts.sh`、`systemd.sh`、`uninstall.sh`、`installer.sh`、`cli.sh`，避免维护两份重复脚本。安装后共享库会复制到 `/usr/local/lib/github520-arch/` 或 `/usr/local/lib/github520-deploy/`。

`bootstrap.sh` 提供：

- 启动时先显示非 Stable 预发布警告
- 检查 Linux、Bash 4+、curl、`/dev/tty` 和 git
- git 缺失时只打印对应发行版安装命令，不自动安装
- 五个仓库源选择（默认 GitCode）
- 临时目录 + `git clone --depth 1`
- 检查 `install.sh`、两个入口和 `lib/` 共享库后，用 `/dev/tty` 启动安装

`install.sh` 提供：

- 启动时先显示非 Stable 预发布警告
- 主动请求 sudo
- 第一次中英猫娘欢迎语
- 显示系统信息：OS、HostName、UserName、版本、内核、架构、Root FS、Virt、systemd、选中入口和仓库目录
- 60 秒倒计时确认（默认取消）
- 拉起前执行 `bash -n` 语法检查（共享库和选中入口）
- 根据发行版自动选择 Arch 版或通用版
- 拒绝直接运行仓库副本的 `install`，统一入口安装

两个平台入口共享的核心提供：

- 实际命令运行前显示非 Stable 预发布警告
- 第二次猫娘风格欢迎与结束语
- 再次检测发行版；通用版额外检测 WSL/Docker 与 KVM/QEMU/Hyper-V
- root/sudo 权限处理
- Btrfs/snapper 快照（选项 3 可不建快照继续）
- 彩色启动日志（`[ INFO ]`、`[  OK  ]`、`[ WARN ]`、`[ FAIL ]`、`[ ALERT ]`），非 TTY 与 systemd 模式自动去色
- 多源 GitHub520 下载与自动回退
- `/etc/hosts` 备份、更新与恢复
- 可选静态 IPv4/DNS
- DNS 可达性与真实解析校验，失败可重试或恢复旧配置
- systemd service + hourly timer
- 状态、日志、手动刷新、重装、卸载
- 原始 hosts 备份与完整卸载恢复

> **非官方声明**：本项目是独立的第三方工具，不是 GitHub520 官方项目，与 [521xueweihan/GitHub520](https://github.com/521xueweihan/GitHub520) 及其作者没有隶属、合作或背书关系。
>
> **上游许可证**：核查时，上游 GitHub520 仓库没有 `LICENSE` 文件，GitHub API 的 `license` 字段为 `null`。因此**不能将上游项目视为 MIT 或任何开源许可证下的项目**；上游代码和内容的权利归原作者，复用、修改或再分发前请先取得授权。
>
> **本项目范围**：仓库不包含上游源码或 hosts 文件；脚本仅在运行时通过 HTTPS 从上游及镜像下载 hosts 数据。本项目自身代码采用 MIT 许可证，见 [LICENSE](LICENSE)，该许可证不覆盖上游项目或其内容。
>
> **AI 辅助声明**：本项目在编写过程中使用了 AI 编程助手；AI 生成内容不会自动发布，最终版本由维护者审阅后决定。详见 [AI 辅助开发声明](#ai-辅助开发声明)。
>
> **发布状态**：当前为 **v1.0.1-rc**（Release Candidate）；**Stable v1.0.1** 将在 RC 验证后发布。RC 前仍可能有行为调整，请保留备份。
>
> **仓库更新**：新增 `packaging/arch` 与 `packaging/debian` 原生包构建文件；安装原生包不会自动修改 `/etc/hosts`，仍需手动执行 `install` 并确认网络设置。
>
> `bootstrap.sh`、`install.sh` 与两个脚本均为 **v1.0.1-rc**，请先备份并在测试机验证。

---

## 推荐使用短链：一键引导

如果不想手动 `git clone`，推荐直接使用短链。短链返回仓库中的 `bootstrap.sh`，由它检查环境、让你选择仓库源并自动 clone，然后调用 `install.sh`：

```bash
curl -fsSL https://get.whitesocks-crs.top/bootstrap.sh -o bootstrap.sh
bash bootstrap.sh
```

> 短链只负责下载引导脚本，不会自动安装软件包；建议先查看 `bootstrap.sh` 内容再执行。

---

## 获取仓库（五选一）

| 源 | 克隆命令 |
|---|---|
| **GitHub** | `git clone https://github.com/WS-CatGirl/github520-deploy.git` |
| **Gitee** | `git clone https://gitee.com/wscatgirl/github520-deploy.git` |
| **GitCode** | `git clone https://gitcode.com/WS_CatGirl/github520-deploy.git` |
| **Codeberg** | `git clone https://codeberg.org/WS_CatGirl/github520-deploy.git` |
| **Gitea** | `git clone https://gitea.com/WS-CatGirl/github520-deploy.git` |

> **反馈与维护说明**：本仓库以 GitHub 为主仓库，**Issue、Bug 报告和功能建议请优先发到 [GitHub Issues](https://github.com/WS-CatGirl/github520-deploy/issues)**。Gitee、GitCode、Codeberg、Gitea 主要作为代码镜像，会同步代码；Tags、Issues 和 Release 说明等以 GitHub 为准，镜像平台很少单独处理，请不要在多个平台重复提交。
>
> **五个源内容相同，任选一个即可，不要重复克隆。**
>
> Gitee 的 HTTPS clone 可能要求登录；bootstrap 支持 Gitee token，默认仍使用 GitCode。

### Gitee HTTPS 登录（可选）

Gitee 公开仓库的 HTTPS clone 也可能要求登录。`bootstrap.sh` 选择 Gitee 时，会按以下顺序读取 token：

1. 环境变量 `GITEE_TOKEN`，同时用 `GITEE_USERNAME` 指定 token 所属账号；
2. `~/.config/github520-deploy/gitee-token`，文件内容只放 token，权限必须是 `600` 或 `400`；
3. 运行时隐藏输入；直接回车则尝试匿名 clone。

创建 token：<https://gitee.com/profile/personal_access_tokens>，建议只授予 `projects` 读取权限。token 只作为 HTTPS 密码发送给 `gitee.com`，不会写入仓库、命令行参数或日志；临时 `askpass.sh` 和 token 文件会在 clone 成功后删除，即使保留 clone 也会删除。

如果你已经下载了仓库（或单独保存了 `askpass.sh`），可以手动使用：

```bash
chmod 600 ~/.config/github520-deploy/gitee-token
export GITEE_USERNAME=你的Gitee用户名
export GITEE_TOKEN_FILE=~/.config/github520-deploy/gitee-token
GIT_ASKPASS=./askpass.sh GIT_ASKPASS_REQUIRE=force \
  git -c credential.helper= clone https://gitee.com/wscatgirl/github520-deploy.git
```

不要把 token 写进 URL、`.git/config`、脚本或 Issue；如果 token 泄露，立即在 Gitee 设置中撤销并重新生成。

---

## 目录

- [推荐使用短链：一键引导](#推荐使用短链一键引导)
- [获取仓库（五选一）](#获取仓库五选一)
  - [Gitee HTTPS 登录（可选）](#gitee-https-登录可选)
- [选择哪个脚本](#选择哪个脚本)
- [Bootstrap 一键引导](#bootstrap-一键引导)
- [功能对比](#功能对比)
- [系统要求](#系统要求)
- [安装](#安装)
- [PATH 与 CLI](#path-与-cli)
- [命令一览](#命令一览)
- [安装流程](#安装流程)
- [Btrfs 与 snapper 快照](#btrfs-与-snapper-快照)
- [网络检测与静态 IP/DNS](#网络检测与静态-ipdns)
- [systemd timer 与 service](#systemd-timer-与-service)
- [日志与备份](#日志与备份)
- [卸载](#卸载)
- [安全说明](#安全说明)
- [AI 辅助开发声明](#ai-辅助开发声明)
- [许可证与上游声明](#许可证与上游声明)
- [常见问题 Q&A](#常见问题-qa)
- [English](#english)

---

## 选择哪个脚本

实际安装统一由 `install.sh` 自动选择，不需要手动运行两个入口。

### `install.sh` 会选择 Arch 版，如果：

- 系统是 Arch Linux（`/etc/os-release` 中 `ID=arch`）；
- 使用 NetworkManager 或 systemd-networkd；
- 希望使用 Arch 专用的 CLI 和 timer 名称。

### `install.sh` 会选择通用版，如果：

- 系统是 Debian、Ubuntu、Fedora、CentOS、Rocky、AlmaLinux、openSUSE 等；
- 需要通用 Linux（非 Arch）支持；
- 更常使用 ifupdown 管理网络；
- 需要显式拒绝 WSL/Docker 容器，并对 KVM/QEMU/VMware/Hyper-V 虚拟机给出警告。

安装统一使用：

```bash
bash ./install.sh
```

> 直接执行 `sudo ./Github520-Arch.sh install` 或 `sudo ./github520-deploy.sh install` 会被拒绝，并提示使用 `install.sh`。
>
> **不要在同一台机器同时安装两个脚本的 timer。** 它们都会修改 `/etc/hosts`，可能互相覆盖。请只选择一个。

## Bootstrap 一键引导

`bootstrap.sh` 适合“先运行一个很小的引导脚本，再选择仓库源”的场景。它不会自动安装软件包，也不会直接修改系统配置。

流程：

```text
检查 Linux / Bash 4+ / curl / /dev/tty / git
→ 显示五个仓库源
→ 用户选择
→ mktemp 创建临时目录
→ git clone --depth 1
   ├─ 成功 → 检查文件
   └─ 3 次失败 → [r] 重选源 / [q] 退出
→ 检查 install.sh / 共享库 / 两个入口
→ bash install.sh < /dev/tty
   ├─ 成功 → 清理临时目录
   └─ 失败 → [k] 保留克隆 / [d] 删除
```

说明：

- Git 缺失时只打印对应发行版的安装命令，然后退出；不会自动调用包管理器；
- 默认源是 GitCode，适合国内网络；Gitee 的 HTTPS clone 可能要求登录，可选择输入 token；
- 五个源分别为 GitHub、Gitee、GitCode、Codeberg、Gitea；
- clone 失败会重试 3 次；仍失败时可 `[r]` 重新选择仓库源，或 `[q]` 退出；
- 脚本使用 `/dev/tty` 读取选择和安装确认，因此兼容 `curl | bash` 的管道模式；
- 安装成功会自动清理临时目录；安装失败时会询问 `[k]` 保留克隆（默认，便于排查）或 `[d]` 删除，选择保留会打印本地仓库路径和之后手动删除的命令；
- 建议先下载查看再运行，不要用 `sudo` 直接执行远端脚本。

短链入口：

```text
https://get.whitesocks-crs.top/bootstrap.sh
```

> Pages 默认域名和 `get.whitesocks-crs.top` 自定义域名均已验证，返回同一份脚本。

## 功能对比

| 项目 | Github520-Arch.sh | github520-deploy.sh |
|---|---|---|
| 安装入口 | `install.sh` 自动选择 | `install.sh` 自动选择 |
| 直接执行 install | 拒绝，提示使用 `install.sh` | 拒绝，提示使用 `install.sh` |
| 系统检查 | 仅 Arch Linux（`ID=arch`） | 非 Arch Linux（需 systemd）；检测到 Arch 会强制退出 |
| WSL/容器 | 未单独判断；通常因 systemd 检查失败而退出 | WSL、Docker、Podman、LXC 等直接退出 |
| 虚拟机 | 无单独 VM 警告 | KVM/QEMU/VMware/Hyper-V 等仅警告并继续 |
| 静态网络优先级 | NetworkManager → systemd-networkd → ifupdown | **ifupdown → NetworkManager → systemd-networkd** |
| CLI | `/usr/local/bin/github520-arch` | `/usr/local/bin/github520-deploy` |
| 兼容入口 | `github520-arch.sh` | `github520-deploy.sh` |
| Service | `github520-update.service` | `github520-deploy-update.service` |
| Timer | `github520-update.timer` | `github520-deploy-update.timer` |
| 日志 | `/var/log/github520/update.log` | `/var/log/github520-deploy/update.log` |
| 备份 | `/var/backups/github520` | `/var/backups/github520-deploy` |
| 原始 hosts | `/var/backups/github520/hosts.original` | `/var/backups/github520-deploy/hosts.original` |

## 系统要求

- Linux
- systemd
- bash 4+
- `sudo`（非 root 运行 `install.sh` 时）
- `stty`（coreutils，用于 60 秒倒计时）
- `curl`
- `ip`（iproute2）
- `findmnt`、`awk`、`sed`、`grep`、`mktemp`、`install`
- `git`（仅克隆仓库时）
- 可选：
  - Btrfs + `snapper` + `btrfs-progs`
  - NetworkManager、systemd-networkd 或 ifupdown
  - systemd-resolved / resolvconf / nscd / dnsmasq

`bootstrap.sh` 另外需要可用的 `/dev/tty`、`git` 和 `curl`；缺少 Git 时只提示安装命令，不自动安装。

`Github520-Arch.sh` 额外要求 `/etc/os-release` 中 `ID=arch`。

## 安装

使用上方“获取仓库（五选一）”完成克隆后，进入目录并运行统一安装器：

```bash
cd github520-deploy
bash ./install.sh
```

也可以使用 `bootstrap.sh` 选择仓库源并自动 clone，详见上面的 [Bootstrap 一键引导](#bootstrap-一键引导)。

`install.sh` 会主动请求 sudo、检测系统、显示信息、60 秒确认，然后自动选择并拉起 Arch 或通用脚本；也可以显式运行 `sudo bash ./install.sh`。

它依次执行：

1. 显示第一次中英猫娘欢迎语；
2. 检测发行版、内核、架构、systemd；
3. 显示系统信息；
4. 60 秒倒计时确认（默认取消）；
5. 检查共享库和对应入口存在，并对 `lib/*.sh` 与选中入口执行 `bash -n`；
6. 按发行版拉起：
   - `ID=arch` → `Github520-Arch.sh`
   - 其他 systemd Linux → `github520-deploy.sh`
7. 入口再次检测发行版；通用版还会检测 WSL/Docker 与 KVM/QEMU/Hyper-V。随后显示第二次欢迎语并继续安装。

> 不要直接运行 `sudo ./Github520-Arch.sh install` 或 `sudo ./github520-deploy.sh install`。这会被拒绝，并提示使用 `install.sh`。
>
> 安装完成后使用 `github520-arch` / `github520-deploy` 管理，不再需要仓库里的子脚本。

安装后：

```bash
sudo github520-arch status
sudo github520-arch update

sudo github520-deploy status
sudo github520-deploy update
```

## PATH 与 CLI

两个 CLI 都安装到 `/usr/local/bin`：

```text
/usr/local/bin/github520-arch
/usr/local/bin/github520-deploy
```

`/usr/local/bin` 是标准 PATH 目录，通常也在 sudo 的 `secure_path` 中，因此可以在 `/home` 等任意目录执行：

```bash
cd /home
sudo github520-arch status
sudo github520-deploy status
```

脚本**不会修改** `/etc/profile` 或 `.bashrc`。

如果自定义 sudoers 的 `secure_path` 不包含 `/usr/local/bin`，使用完整路径：

```bash
sudo /usr/local/bin/github520-arch status
sudo /usr/local/bin/github520-deploy status
```

同时会创建兼容入口：

```text
/usr/local/bin/github520-arch.sh   -> /usr/local/bin/github520-arch
/usr/local/bin/github520-deploy.sh -> /usr/local/bin/github520-deploy
```

入口需要的共享库安装到：

```text
/usr/local/lib/github520-arch/
  github520-common.sh
  core.sh
  snapshots.sh
  network.sh
  ssh.sh
  hosts.sh
  systemd.sh
  uninstall.sh
  installer.sh
  cli.sh
  platform-arch.sh

/usr/local/lib/github520-deploy/
  github520-common.sh
  core.sh
  snapshots.sh
  network.sh
  ssh.sh
  hosts.sh
  systemd.sh
  uninstall.sh
  installer.sh
  cli.sh
  platform-generic.sh
```

`--uninstall` 和 `--uninstall-completely` 都会删除对应的共享库目录喵。

## 命令一览

仓库安装使用 `bash ./install.sh`；下表是安装完成后的 CLI 管理命令。

以下命令对两个 CLI 都适用，只需替换命令名：

- Arch：`github520-arch`
- 通用：`github520-deploy`

| 命令 | 说明 |
|---|---|
| `sudo <cli>` | 显示状态和简短帮助 |
| `sudo <cli> install` | 首次应用 hosts、网络和 timer；发现已有 CLI、hosts 块或 timer/service 则拒绝 |
| `sudo <cli> reinstall` | 跳过已安装检测，使用当前 CLI 重新部署 |
| `sudo <cli> update` | 立即拉取并刷新 hosts |
| `sudo <cli> refresh` | `update` 别名 |
| `sudo <cli> status` | 状态、hosts 条目、timer、最近日志、备份数 |
| `sudo <cli> logs` | 查看更新日志 |
| `sudo <cli> logs -f` | 实时跟踪日志 |
| `sudo <cli> restore` | 恢复最近备份 |
| `sudo <cli> restore original` | 恢复安装前原始 hosts |
| `sudo <cli> restore FILE` | 恢复指定备份 |
| `sudo <cli> --uninstall` | 删除 CLI/unit，保留 hosts、日志、备份 |
| `sudo <cli> --uninstall-completely` | 恢复原始 hosts 并删除全部数据 |
| `sudo <cli> --uninstall-completely --force` | 跳过完整卸载确认 |
| `<cli> version` | 版本 |
| `<cli> help` | 帮助 |

示例：

```bash
sudo github520-deploy update
sudo github520-deploy logs -f
sudo github520-arch --uninstall
sudo github520-deploy --uninstall-completely
```

Systemd 内部模式：

```bash
/usr/local/bin/github520-arch --update --systemd
/usr/local/bin/github520-deploy --update --systemd
```

## 安装流程

### 可选引导入口 `bootstrap.sh`

```text
运行 bootstrap.sh
  ↓
检查 Linux / Bash / curl / tty / git
  ↓
五选一仓库源
  ↓
临时目录 + git clone --depth 1
  ↓
检查 install.sh、共享库和两个入口
  ↓
bash install.sh < /dev/tty
```

### 统一入口 `install.sh`

```text
用户 git clone（五选一）
  ↓
bash ./install.sh
  ↓
主动请求 sudo
  ↓
第一次欢迎语
  ↓
检测发行版 / 内核 / 架构 / systemd
  ↓
检查子脚本和模块 + bash -n
  ↓
已安装检测（CLI + hosts 块 + timer/service）
  ↓
显示系统信息
  ↓
60 秒倒计时（默认取消）
  ↓
按发行版拉起
  ├─ Arch → Github520-Arch.sh install
  └─ 其他 → github520-deploy.sh install
```

### 子脚本第二阶段

```text
第二次欢迎语
  ↓
再次检测发行版
  ├─ 通用版：拒绝 Arch；WSL/Docker/Podman/LXC 退出；VM 警告
  └─ Arch 版：仅接受 ID=arch；systemd 检查
  ↓
root / sudo 检查
  ↓
已安装检测（CLI + hosts 块 + timer/service；`reinstall` 跳过）
  ↓
首次备份原始 /etc/hosts
  ↓
Btrfs + snapper 可选快照
  ↓
网络后端检测
  ↓
GitHub520 下载并备份、更新 hosts
  ↓
询问是否配置静态 IPv4 / DNS
  ↓
验证静态 IP / DNS（失败可重试或恢复）
  ↓
安装 CLI + hourly timer
  ↓
清理临时文件并输出总结
```

### 已安装检测

`install.sh` 在确认安装前会预检一次，子脚本在 root 检查之后、备份 hosts 之前还会再检查一次，共三层：

1. **CLI 检测**：检查 `INSTALL_PATH`、`/usr/local/bin/<cli>`、`/usr/bin/<cli>`，以及兼容用的 `.sh` 路径。当前正在运行的 CLI 会被排除，所以包安装后的首次 `install` 不会误判。
2. **hosts 检测**：检查 `/etc/hosts` 中是否存在 GitHub520 的 start/end 标记；即使块内没有条目也会命中。
3. **systemd 检测**：检查 `/etc/systemd/system` 下的源码安装 unit，以及 timer/service 是否处于 enabled/active 状态。包自带的 `/usr/lib` 或 `/lib` unit 不算已配置，避免刚装包就被误判。

任一命中都会打印具体原因，并以退出码 1 结束；此时不会备份 hosts、不会修改网络、不会安装 timer。`reinstall` 会显式跳过检测，用于已安装 CLI 的重新部署。

网络后端优先级：

- 通用版：ifupdown → NetworkManager → systemd-networkd；
- Arch 版：NetworkManager → systemd-networkd → ifupdown。

## Btrfs 与 snapper 快照

两个脚本都支持：

```text
1) Snapshot all snapper configs
2) Snapshot only the @ subvolume (root config)
3) Continue without a snapshot (requires YES confirmation)
4) Abort deployment
```

- 30 秒实时倒计时（仅 Btrfs 快照菜单）；
- 选择 3 后会显示鲜红色 `[ ALERT ]` 警告，并要求在 30 秒内输入全大写 `YES` 并按回车；
- 超时、snapper/btrfs 错误、拒绝确认或选择 4 都会中止；
- 选择 3 不创建任何快照，但会继续执行安装；
- 非 Btrfs 时显示醒目的 `[ WARN ]`，**不倒计时**，只有输入 `y`/`yes` 才继续；`n` 或直接回车取消安装；
- Btrfs 但没有 snapper 配置时自动跳过；
- 选择 1/2 时，快照发生在写 hosts 和改网络之前。

## 网络检测与静态 IP/DNS

### 优先级

| 脚本 | 优先级 |
|---|---|
| `github520-deploy.sh` | **ifupdown → NetworkManager → systemd-networkd** |
| `Github520-Arch.sh` | **NetworkManager → systemd-networkd → ifupdown** |

### 通用版为什么优先 ifupdown

通用 Linux 发行版中 ifupdown 仍然常见（尤其是服务器和 minimal 安装）。脚本会先查找 `/etc/network/interfaces` 及 `interfaces.d` 中目标接口的 stanza，再考虑 NetworkManager。

> 如果接口实际由 NetworkManager 管理，但系统里同时存在旧的 ifupdown 配置，优先 ifupdown 可能不会作用到当前活动连接。请先确认接口实际由谁管理，必要时先清理旧配置。

### 静态配置方式

- ifupdown：只重写目标 IPv4 stanza，`inet6` stanza 会保留；IPv4 的复杂选项（MTU、bridge、bond、VLAN、pre-up）可能丢失；
- NetworkManager：`nmcli connection modify` + reactivate；
- systemd-networkd：写 99 优先级 `.network` 文件并 reload。

修改静态 IP/DNS 会保存旧配置；验证失败时尝试回滚。

### DNS 校验与失败恢复

应用 IP/DNS 后，脚本会验证 DNS：

- 先确认新 DNS 已实际生效；
- `ping` 可用时检查 DNS 服务器可达性；`ping` 缺失只警告，不阻塞；
- 优先用 `dig @DNS example.com`，否则用 `getent ahostsv4 example.com` 或 `resolvectl query` 做真实解析；
- 最多尝试 3 次，每次间隔 2 秒；
- 3 次失败后提示：
  - `[r]` 重试验证；
  - `[c]` 从空白重新输入 DNS，并按当前后端重新应用；
  - `[a]` 恢复旧网络配置，随后询问 `[k]` 保留并继续安装，或 `[a]` 取消安装；
- 不安装任何软件包；工具缺失时按可用工具降级。

### 风险

- 修改 IP 或重启网络可能中断 SSH；
- **SSH 环境安全闸门**：检测到 `SSH_CONNECTION`、`SSH_CLIENT`、`SSH_TTY`、安装器传递的 SSH 标记，或进程祖先中有 `sshd` / `sshd-session` / `dropbear` / `mosh-server` 时，脚本会在进入 IP/DNS 修改前显示鲜红色警告；必须输入**全大写 `YES`**才会继续，其他任何输入都会跳过静态 IP/DNS 修改并继续后续安装；
- `/etc/resolv.conf` 是符号链接时不会直接覆盖；
- 没有 IPv4 默认路由时会跳过静态网络配置，hosts 更新继续；
- 优先使用本地控制台或云控制台。

## systemd timer 与 service

| 项目 | Arch 版 | 通用版 |
|---|---|---|
| Service | `github520-update.service` | `github520-deploy-update.service` |
| Timer | `github520-update.timer` | `github520-deploy-update.timer` |
| ExecStart | `github520-arch --update --systemd` | `github520-deploy --update --systemd` |
| 日志 | `/var/log/github520/update.log` | `/var/log/github520-deploy/update.log` |

Timer 行为相同：

- 安装完成后立即更新一次 hosts；
- 开机 5 分钟后首次运行；
- 之后每小时运行一次；
- 更新成功/失败写入日志；
- 手动更新与 timer 共用 `/run/github520-hosts.lock`，不会同时写 hosts；
- 更新模式不创建快照、不改网络、不重装 timer。

常用命令：

```bash
# Arch
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
journalctl -u github520-update.service

# 通用
systemctl status github520-deploy-update.timer
systemctl list-timers github520-deploy-update.timer
journalctl -u github520-deploy-update.service
```

## 日志与备份

| 项目 | Arch 版 | 通用版 |
|---|---|---|
| 日志 | `/var/log/github520/update.log` | `/var/log/github520-deploy/update.log` |
| 原始 hosts | `/var/backups/github520/hosts.original` | `/var/backups/github520-deploy/hosts.original` |
| 时间戳备份 | `/var/backups/github520/hosts.<时间>.<pid>` | `/var/backups/github520-deploy/hosts.<时间>.<pid>` |
| 网络备份 | `/var/backups/github520/net-<时间>.<pid>/` | `/var/backups/github520-deploy/net-<时间>.<pid>/` |

- 原始 hosts 只在首次安装时保存，不会被后续安装覆盖；
- 时间戳备份默认保留最近 24 份；
- 更新日志超过 1 MiB 会轮转为 `.1`；
- 临时文件在退出或安装结束时清理。

## 卸载

### 保留数据卸载

```bash
# Arch
sudo github520-arch --uninstall

# 通用
sudo github520-deploy --uninstall
```

会删除 CLI、兼容入口和 systemd unit，但保留 hosts、日志、备份。

### 完整卸载

```bash
# Arch
sudo github520-arch --uninstall-completely

# 通用
sudo github520-deploy --uninstall-completely
```

会：

1. 停止并删除 systemd units；
2. 恢复各自的 `hosts.original`（不存在则用最近备份）；
3. 从恢复后的 hosts 中移除 GitHub520 块；
4. 删除 CLI、兼容入口；
5. 删除对应日志和备份目录；
6. 删除旧式 `/etc/hosts.github520-backup.*`；
7. 清理对应临时文件。

完整卸载会要求确认；`--force` 可跳过：

```bash
sudo github520-deploy --uninstall-completely --force
```

> 完整卸载恢复的是首次安装前的 hosts，因此安装后手动添加的其他 hosts 修改也可能丢失。需要保留时使用 `--uninstall`，或先手动备份当前 `/etc/hosts`。

## 安全说明

- `install.sh` 主动请求 sudo，以 root 修改 hosts、网络配置并安装 systemd unit。
- `bootstrap.sh` 只检查环境、选择源并 clone，不会安装软件包或直接修改系统；建议先查看脚本内容再运行。
- 子脚本直接执行 `install` 会被拒绝，必须通过 `install.sh` 安装。
- hosts 内容来自 GitHub520 及第三方 CDN/镜像；脚本校验结构和条目数量，但**没有域名白名单**。
- 下载仅允许 HTTPS，并拒绝从 HTTPS 跳转到 HTTP。
- Timer 以 root 执行本地脚本；确保 `/usr/local/bin/github520-arch` 或 `/usr/local/bin/github520-deploy` 归 root 所有且不可被普通用户写入。
- 脚本不会安装软件包、修改防火墙或 SSH 配置。
- 两个脚本的 timer 不应当同时启用。
- 当前为 **v1.0.1-rc**，请保留快照和备份；`bootstrap.sh` 会在正式使用前检查环境。

## AI 辅助开发声明

本项目的代码、脚本注释和文档在编写过程中使用了 AI 编程助手，包括生成草稿、代码片段和文字润色。AI 生成内容不会自动发布；是否合并、修改和发布由维护者决定，最终版本经过维护者人工审阅，并在条件允许时进行了实际测试。

需要明确的是：

- 本项目按 **“现状”（AS IS）** 提供，不附带任何明示或暗示的担保，包括但不限于适销性、特定用途适用性和不侵权；
- AI 辅助内容可能存在错误、遗漏、潜在安全问题、过时信息，或与你的发行版、硬件、网络环境不兼容；使用前请自行阅读脚本、备份数据，并在测试环境中验证；
- 因使用、修改或分发本项目而产生的任何直接或间接损失，作者及贡献者在适用法律允许的范围内不承担责任；
- 本项目不是 GitHub520 官方项目，与上游作者没有隶属、合作或背书关系；上游代码和 hosts 内容的权利归其原作者，详见下文 [许可证与上游声明](#许可证与上游声明)；
- 本声明不改变本项目自身代码的 MIT 许可证，也不构成法律意见。

## 许可证与上游声明

### 本项目

本仓库的脚本、`install.sh`、`bootstrap.sh` 和文档由 **白丝小猫娘 (WS-CatGirl)** 维护并发布，采用 **MIT License**，完整文本见 [LICENSE](LICENSE)。

该 MIT 许可证只覆盖本仓库自身的代码和文档，**不覆盖** GitHub520 上游项目、其代码或其 hosts 内容。

### GitHub520 上游

- 上游仓库：[521xueweihan/GitHub520](https://github.com/521xueweihan/GitHub520)
- 核查时，上游仓库**没有 `LICENSE` 文件**，GitHub API 的 `license` 字段为 `null`；
- 因此不能把上游项目描述为 MIT 或其他开源许可证项目；上游代码和内容的权利归原作者，默认保留相关权利；
- 如需复用、修改或再分发上游代码或内容，请先联系上游作者取得明确授权；
- 本项目是独立的第三方工具，**不是 GitHub520 官方项目**，与上游作者没有隶属、合作或背书关系。

### 数据获取方式

本仓库不包含上游源码或 hosts 文件。脚本仅在运行时通过 HTTPS 从 GitHub520 及第三方镜像下载 hosts 数据，用于更新本机 `/etc/hosts`。

> 以上为仓库状态说明，不构成法律意见；涉及再分发或商业使用时请自行确认授权。

## 常见问题 Q&A

### Q1: 应该选哪个脚本？

实际安装由 `install.sh` 自动选择：

- `ID=arch`：`Github520-Arch.sh`；
- 其他 Linux：`github520-deploy.sh`。

### Q2: 两个脚本可以同时安装吗？

技术上安装路径和 unit 名称不同，但两个 timer 都会改 `/etc/hosts`，会互相覆盖。**不要同时启用两个 timer**，只选一个。

### Q3: 为什么 `sudo github520-arch` / `sudo github520-deploy` 显示状态而不是安装？

为了防止误重装。仓库安装使用：

```bash
cd github520-deploy
bash ./install.sh
```

已安装 CLI 的 `install` 会先检查是否已有安装，发现冲突就报错退出；`reinstall` 会跳过该检查，用当前 CLI 重新部署。

### Q4: 命令提示 not found？

确认文件存在：

```bash
ls -l /usr/local/bin/github520-arch
ls -l /usr/local/bin/github520-deploy
```

如果 sudo 找不到，使用完整路径。脚本不会修改 `/etc/profile` 或 `.bashrc`；部分自定义 sudoers 的 `secure_path` 可能不含 `/usr/local/bin`。

### Q5: 如何立即刷新 hosts？

```bash
sudo github520-arch update
# 或
sudo github520-deploy update
```

### Q6: 如何查看日志？

```bash
sudo github520-arch logs -f
# 或
sudo github520-deploy logs -f
```

### Q7: 通用版为什么优先 ifupdown？

因为通用 Linux 服务器上 ifupdown 仍很常见。脚本先查找 ifupdown 配置，再回退到 NetworkManager/systemd-networkd。Arch 版则优先 NetworkManager。

### Q8: 通用版在虚拟机里会退出吗？

不会。KVM/QEMU/VMware/Hyper-V 等只警告并继续；WSL、Docker、Podman、LXC 等容器会直接退出。

### Q9: Arch 版在 WSL/容器里能用吗？

Arch 版没有单独的 WSL/容器判断，但要求 systemd 和 `/run/systemd/system`；大多数 WSL/容器环境会在 systemd 检查处失败。

### Q10: `--uninstall` 和 `--uninstall-completely` 有什么区别？

- `--uninstall`：删除 CLI/unit，保留 hosts、日志、备份；
- `--uninstall-completely`：恢复原始 hosts，并删除 CLI、unit、日志、备份和临时文件。

### Q11: 完整卸载会恢复什么 hosts？

各自的 `hosts.original`；没有则使用最近时间戳备份；都没有则从当前 hosts 删除 GitHub520 块。

### Q12: 安装后手动改过 hosts，完整卸载会保留吗？

不会。完整卸载以首次安装前的 hosts 为基准。需要保留时用 `--uninstall`，或先手动备份当前 `/etc/hosts`。

### Q13: 快照菜单超时了？

30 秒内必须选择 1 到 4。选择 3 后还需要在 30 秒内输入全大写 `YES` 并按回车；任何一步超时都会中止，不修改 hosts 或网络。

### Q14: 所有 GitHub520 源都失败？

脚本会在修改 hosts 前退出。检查网络、DNS、代理、防火墙、TLS 拦截和系统时间。

### Q15: 静态 IP 修改后 SSH 断线？

新版在 SSH 环境下会先显示红色安全警告，必须输入全大写 `YES` 才会进入 IP/DNS 修改；其他输入会直接跳过该步骤。但 `YES` 只表示你确认风险，**不能保证 SSH 不断线**。仍建议优先使用本地/云控制台；如果已经断线，使用控制台查看对应 `/var/backups/github520*` 的 `net-*` 目录，恢复配置并重启网络后端，或恢复快照。

### Q16: 如何重装/更新脚本？

如果只是用已安装版本重新部署：

```bash
sudo github520-arch reinstall
# 或
sudo github520-deploy reinstall
```

如果要从仓库安装新版本，先完整卸载，再重新运行安装器：

```bash
sudo github520-arch --uninstall-completely
cd github520-deploy
bash ./install.sh
```

`install.sh` 默认会检查已有 CLI 和 `/etc/hosts` 里的 GitHub520 块，发现已安装就报错退出；`reinstall` 才会跳过这个检查。`reinstall` 只使用已安装 CLI 重新部署，不会从网络下载新版本。

### Q17: 这是正式版吗？

不是正式版。当前为 **v1.0.1-rc**（Release Candidate）；**Stable v1.0.1** 将在 RC 验证后发布。请先备份并反馈问题。

### Q18: 为什么直接运行子脚本安装会被拒绝？

为了防止在错误发行版上装错版本，仓库里的两个入口只允许由 `install.sh` 拉起安装。直接执行 `sudo ./Github520-Arch.sh install` 或 `sudo ./github520-deploy.sh install` 会报错，并提示：

```bash
cd github520-deploy
bash ./install.sh
```

已安装 CLI 的 `update`、`status`、`logs`、`restore`、`--uninstall` 等命令不受影响。

### Q19: 通过 `install.sh` 还会选错 Arch/通用版吗？

正常不会。`install.sh` 根据 `/etc/os-release` 的 `ID` 选择：`ID=arch` 用 Arch 版，其他用通用版；子脚本启动后还会再次检测，选错会直接报错。

### Q20: DNS 填错了会怎样？

应用 IP/DNS 后，脚本会检查 DNS 服务器可达性（`ping` 可用时），并用 `dig`、`getent` 或 `resolvectl` 做真实解析；最多尝试 3 次。失败后可 `[r]` 重试、`[c]` 从空白重新输入 DNS 并重新应用，或 `[a]` 恢复旧网络配置；恢复后选择 `[k]` 保留并继续安装，或 `[a]` 取消安装。

---

# English

This repository contains a bootstrap script, a unified installer, two GitHub520 hosts manager entries, and the shared `lib/` implementation they use:

| File | Purpose | CLI |
|---|---|---|
| **bootstrap.sh** | Bootstrap: checks the environment, selects a source, clones, then calls `install.sh` | — |
| **install.sh** | Unified installer; detects the platform and launches the right script | — |
| **Github520-Arch.sh** | Thin Arch Linux entry (`ID=arch`) | `github520-arch` |
| **github520-deploy.sh** | Thin generic Linux entry (non-Arch, systemd) | `github520-deploy` |
| **lib/github520-common.sh** | Module loader; all implementation lives in the other `lib/*.sh` files | — |
| **lib/core.sh** | Global state, output, traps, privileges, OS checks and terminal helpers | — |
| **lib/snapshots.sh** | Btrfs / snapper snapshot detection and creation | — |
| **lib/network.sh** | Network backend detection, static IPv4/DNS, validation and rollback | — |
| **lib/ssh.sh** | SSH session/ancestor detection and the red safety warning | — |
| **lib/hosts.sh** | GitHub520 download, validation, hosts generation, backup and atomic install | — |
| **lib/systemd.sh** | Installed CLI/module copy, service and timer installation | — |
| **lib/uninstall.sh** | Hosts restore, uninstall, purge, status and logs | — |
| **lib/installer.sh** | Installation workflow, update mode and final summary | — |
| **lib/cli.sh** | Argument parsing, install-source guard and command dispatch | — |
| **lib/platform-arch.sh** | Arch-specific distribution check and network priority | — |
| **lib/platform-generic.sh** | Generic platform hook; currently inherits the common defaults | — |

Both entries are now thin wrappers: `Github520-Arch.sh` / `github520-deploy.sh` select the platform, load the shared library and call `main`. `lib/github520-common.sh` loads `core.sh`, `snapshots.sh`, `network.sh`, `ssh.sh`, `hosts.sh`, `systemd.sh`, `uninstall.sh`, `installer.sh` and `cli.sh` in order, so the duplicate scripts no longer need to be maintained. On installation the shared library is copied to `/usr/local/lib/github520-arch/` or `/usr/local/lib/github520-deploy/`.

`bootstrap.sh` provides:

- A non-Stable pre-release warning before doing anything
- Linux, Bash 4+, curl, `/dev/tty` and git checks
- Manual-install instructions when git is missing; no automatic package installation
- Five repository sources (GitCode is the default)
- Temporary directory + `git clone --depth 1`
- File checks for `install.sh`, both entries and `lib/`, then launches `install.sh` through `/dev/tty`

`install.sh` provides:

- A non-Stable pre-release warning before doing anything
- Proactive sudo request
- First bilingual catgirl welcome
- System information: OS, HostName, UserName, version, kernel, architecture, Root FS, Virt, systemd, selected entry and repository directory
- 60-second confirmation countdown (default: cancel)
- `bash -n` syntax check for the shared library and selected entry before launch
- Automatic selection of the Arch or generic script
- Direct `install` through repository copies is rejected; use the installer

The shared core behind both platform entries provides:

- A non-Stable pre-release warning before actual commands
- Second catgirl welcome and final message
- A second distribution check; the generic script also checks WSL/Docker and KVM/QEMU/Hyper-V
- root/sudo handling
- Btrfs/snapper snapshots (option 3 can continue without one)
- Colored boot-style logs (`[ INFO ]`, `[  OK  ]`, `[ WARN ]`, `[ FAIL ]`, `[ ALERT ]`), with automatic color removal for non-TTY and systemd output
- Multiple GitHub520 sources with fallback
- `/etc/hosts` backup, update and restore
- Optional static IPv4/DNS
- DNS reachability and real-resolution validation, with retry or previous-config restore on failure
- systemd service + hourly timer
- status, logs, manual refresh, reinstall and uninstall
- original hosts backup and complete-uninstall restore

> **Unofficial notice**: This is an independent third-party tool. It is not an official GitHub520 project and has no affiliation, partnership or endorsement relationship with [521xueweihan/GitHub520](https://github.com/521xueweihan/GitHub520) or its author.
>
> **Upstream license**: At the time of review, the upstream GitHub520 repository has no `LICENSE` file and the GitHub API `license` field is `null`. The upstream project must therefore **not** be treated as MIT-licensed or as an open-source-licensed project. Rights to upstream code and content remain with its author; obtain permission before reusing, modifying or redistributing it.
>
> **Scope of this project**: This repository does not bundle upstream source code or the hosts file. The scripts only download hosts data at runtime over HTTPS from upstream and mirrors. This project's own code is MIT-licensed; see [LICENSE](LICENSE). That license does not cover the upstream project or its content.
>
> **AI assistance**: AI coding assistants were used during development. AI output is not published automatically; the maintainer reviews released content. See [AI-assisted development disclosure](#ai-assisted-development-disclosure).
>
> **Release status**: The current version is **v1.0.1-rc** (Release Candidate). **Stable v1.0.1** is expected after RC validation. Behaviour may still change before the stable release; keep backups.
>
> **Repository update**: Native packaging files were added under `packaging/arch` and `packaging/debian`. Installing a package does not modify `/etc/hosts` automatically; run `install` manually and confirm the network options.
>
> `bootstrap.sh`, both scripts and `install.sh` are **v1.0.1-rc**.

## Recommended: short URL

If you do not want to clone the repository manually, use the short URL. It serves the repository's `bootstrap.sh`, which checks the environment, lets you choose a source, clones the repository and then calls `install.sh`:

```bash
curl -fsSL https://get.whitesocks-crs.top/bootstrap.sh -o bootstrap.sh
bash bootstrap.sh
```

> The short URL only downloads the bootstrap script; it does not install packages automatically. Review `bootstrap.sh` before running it.

## Get the repository (choose one of five)

| Source | Clone command |
|---|---|
| **GitHub** | `git clone https://github.com/WS-CatGirl/github520-deploy.git` |
| **Gitee** | `git clone https://gitee.com/wscatgirl/github520-deploy.git` |
| **GitCode** | `git clone https://gitcode.com/WS_CatGirl/github520-deploy.git` |
| **Codeberg** | `git clone https://codeberg.org/WS_CatGirl/github520-deploy.git` |
| **Gitea** | `git clone https://gitea.com/WS-CatGirl/github520-deploy.git` |

> **Issues and maintenance**: GitHub is the primary repository. **Please report bugs and feature requests through [GitHub Issues](https://github.com/WS-CatGirl/github520-deploy/issues).** Gitee, GitCode, Codeberg and Gitea are code mirrors: tags, issues and release notes are handled primarily on GitHub and may not be processed on mirrors. Please do not duplicate issues across platforms.
>
> **All five sources contain the same repository. Choose one only; do not clone all five.**
>
> Gitee HTTPS clone may require login; bootstrap supports a Gitee token and still uses GitCode by default.

### Gitee HTTPS login (optional)

Gitee may require login even for HTTPS clones of public repositories. When Gitee is selected, `bootstrap.sh` reads the token in this order:

1. `GITEE_TOKEN`, with `GITEE_USERNAME` for the token owner;
2. `~/.config/github520-deploy/gitee-token` (token only; mode must be `600` or `400`);
3. A hidden prompt; press Enter to try an anonymous clone.

Create a token at <https://gitee.com/profile/personal_access_tokens> and grant only `projects` read access if possible. The token is sent only to `gitee.com` as the HTTPS password. It is never written to the repository, command-line arguments or logs. The temporary `askpass.sh` and token file are removed after a successful clone, even if the clone is kept.

Manual clones can use the repository's `askpass.sh` once you have a checkout or have saved the file separately:

```bash
chmod 600 ~/.config/github520-deploy/gitee-token
export GITEE_USERNAME=your-gitee-username
export GITEE_TOKEN_FILE=~/.config/github520-deploy/gitee-token
GIT_ASKPASS=./askpass.sh GIT_ASKPASS_REQUIRE=force \
  git -c credential.helper= clone https://gitee.com/wscatgirl/github520-deploy.git
```

Never put the token in a URL, `.git/config`, a script or an issue. Revoke and regenerate it immediately if it leaks.

## Which script?

`install.sh` selects the script automatically. It uses `Github520-Arch.sh` on Arch Linux (`ID=arch`) and `github520-deploy.sh` on other systemd Linux distributions, especially systems using ifupdown.

Install with:

```bash
bash ./install.sh
```

Direct `sudo ./Github520-Arch.sh install` or `sudo ./github520-deploy.sh install` calls are rejected with a hint to use `install.sh`.

Do **not** enable both timers on the same machine; both modify `/etc/hosts`.

## Bootstrap

`bootstrap.sh` is the small entry point for users who want to select a source and clone without setting up the repository manually. It does not install packages or modify the system directly.

```text
check Linux / Bash 4+ / curl / /dev/tty / git
→ show five sources
→ user selects one
→ create a temporary directory
→ git clone --depth 1
   ├─ success → check files
   └─ 3 failures → [r] select another source / [q] quit
→ check install.sh, lib/ and both entries
→ bash install.sh < /dev/tty
   ├─ success → remove the temporary directory
   └─ failure → [k] keep the clone / [d] delete it
```

- If git is missing, it prints distro-specific install commands and exits; it never installs packages automatically.
- GitCode is the default source and works anonymously in China; Gitee HTTPS clone may require login and can use the optional token flow.
- The five sources are GitHub, Gitee, GitCode, Codeberg and Gitea.
- Clone failures are retried three times; if all fail, `[r]` selects another source and `[q]` quits.
- `/dev/tty` is used for selection and installation so piped usage still works.
- On success the temporary directory is removed automatically. On failure the bootstrap asks `[k]` to keep the clone (default, useful for troubleshooting) or `[d]` to delete it; keeping it prints the local repository path and a later removal command.
- Prefer downloading and reviewing the bootstrap before running it instead of piping it directly to a shell.

The short URL is:

```text
https://get.whitesocks-crs.top/bootstrap.sh
```

> Both the Pages project URL and the `get.whitesocks-crs.top` custom domain have been verified to return the same bootstrap script.

## Comparison

| Item | Github520-Arch.sh | github520-deploy.sh |
|---|---|---|
| Installer | selected by `install.sh` | selected by `install.sh` |
| Direct install | rejected; use `install.sh` | rejected; use `install.sh` |
| OS check | Arch only (`ID=arch`) | Non-Arch Linux with systemd; exits on Arch |
| WSL/containers | no explicit check; systemd check usually rejects | WSL/Docker/Podman/LXC exit |
| Virtual machines | no separate VM warning | KVM/QEMU/VMware/Hyper-V warn and continue |
| Static network priority | NetworkManager → networkd → ifupdown | **ifupdown → NetworkManager → networkd** |
| CLI | `github520-arch` | `github520-deploy` |
| Compat entry | `github520-arch.sh` | `github520-deploy.sh` |
| Service | `github520-update.service` | `github520-deploy-update.service` |
| Timer | `github520-update.timer` | `github520-deploy-update.timer` |
| Log | `/var/log/github520/update.log` | `/var/log/github520-deploy/update.log` |
| Backups | `/var/backups/github520` | `/var/backups/github520-deploy` |

## Requirements

- Linux
- systemd
- bash 4+
- `sudo` (when `install.sh` is not run as root)
- `stty` (coreutils, for the 60-second countdown)
- `curl`, `ip`, `findmnt`, `awk`, `sed`, `grep`, `mktemp`, `install`
- `git` (only for cloning the repository)
- Optional: Btrfs + snapper + btrfs-progs
- Optional: NetworkManager, systemd-networkd, ifupdown
- Optional: systemd-resolved, resolvconf, nscd or dnsmasq

`bootstrap.sh` additionally requires `/dev/tty`, `git` and `curl`; when Git is missing it only prints install commands and does not install it automatically.

`Github520-Arch.sh` additionally requires `ID=arch` in `/etc/os-release`.

## Install

After cloning from one of the sources above, enter the directory and run the unified installer:

```bash
cd github520-deploy
bash ./install.sh
```

You can also use `bootstrap.sh` to select a source and clone automatically; see [Bootstrap](#bootstrap) above.

`install.sh` requests sudo, detects the system, shows a summary, asks for confirmation with a 60-second countdown, and then launches the correct script; `sudo bash ./install.sh` also works.

It performs:

1. The first bilingual catgirl welcome.
2. Distribution, kernel, architecture and systemd detection.
3. A system information summary.
4. A 60-second confirmation countdown (default: cancel).
5. A shared-library and selected-entry file check, plus `bash -n` for `lib/*.sh` and the selected entry.
6. Launch by distribution:
   - `ID=arch` → `Github520-Arch.sh`
   - other systemd Linux → `github520-deploy.sh`
7. The entry re-checks the distribution; the generic version also checks WSL/Docker and KVM/QEMU/Hyper-V. It then shows the second welcome and continues.

> Do not run `sudo ./Github520-Arch.sh install` or `sudo ./github520-deploy.sh install` directly. They are rejected with a hint to use `install.sh`.
>
> After installation, manage the tool with `github520-arch` or `github520-deploy`; the repository scripts are no longer needed.

After installation:

```bash
sudo github520-arch status
sudo github520-arch update

sudo github520-deploy status
sudo github520-deploy update
```

## PATH and CLI

Both CLIs are installed under `/usr/local/bin`:

```text
/usr/local/bin/github520-arch
/usr/local/bin/github520-deploy
```

They can be executed from any directory:

```bash
cd /home
sudo github520-arch status
sudo github520-deploy status
```

The scripts do not modify `/etc/profile` or `.bashrc`. If sudo's `secure_path` excludes `/usr/local/bin`, use the full path.

Compatibility symlinks:

```text
/usr/local/bin/github520-arch.sh   -> /usr/local/bin/github520-arch
/usr/local/bin/github520-deploy.sh -> /usr/local/bin/github520-deploy
```

The shared libraries required by the entries are installed under:

```text
/usr/local/lib/github520-arch/
  github520-common.sh
  core.sh
  snapshots.sh
  network.sh
  ssh.sh
  hosts.sh
  systemd.sh
  uninstall.sh
  installer.sh
  cli.sh
  platform-arch.sh

/usr/local/lib/github520-deploy/
  github520-common.sh
  core.sh
  snapshots.sh
  network.sh
  ssh.sh
  hosts.sh
  systemd.sh
  uninstall.sh
  installer.sh
  cli.sh
  platform-generic.sh
```

Both `--uninstall` and `--uninstall-completely` remove the matching shared-library directory.

## Commands

Use `bash ./install.sh` for repository installs. The commands below manage an installed copy.

Replace `<cli>` with `github520-arch` or `github520-deploy`:

| Command | Description |
|---|---|
| `sudo <cli>` | Status and short help |
| `sudo <cli> install` | First-time hosts/network/timer setup; refuses if another CLI, hosts block or timer/service exists |
| `sudo <cli> reinstall` | Skip the existing-install check and redeploy with the current CLI |
| `sudo <cli> update` | Immediately refresh hosts |
| `sudo <cli> refresh` | Alias for update |
| `sudo <cli> status` | Show status, hosts count, timer, last log, backups |
| `sudo <cli> logs` | Show update log |
| `sudo <cli> logs -f` | Follow log |
| `sudo <cli> restore` | Restore latest hosts backup |
| `sudo <cli> restore original` | Restore pre-install hosts |
| `sudo <cli> restore FILE` | Restore a specific backup |
| `sudo <cli> --uninstall` | Remove CLI/units, keep hosts/logs/backups |
| `sudo <cli> --uninstall-completely` | Restore hosts and remove all data |
| `sudo <cli> --uninstall-completely --force` | Skip complete-uninstall confirmation |
| `<cli> version` | Show version |
| `<cli> help` | Show help |

## Install flows

### Optional bootstrap entry: `bootstrap.sh`

```text
run bootstrap.sh
  ↓
check Linux / Bash / curl / tty / git
  ↓
select one of five sources
  ↓
temporary directory + git clone --depth 1
  ↓
verify install.sh, lib/ and both entries
  ↓
bash install.sh < /dev/tty
```

### Unified entry: `install.sh`

```text
git clone (one of five sources)
  ↓
bash ./install.sh
  ↓
request sudo
  ↓
first welcome
  ↓
distribution / kernel / architecture / systemd detection
  ↓
file checks + bash -n
  ↓
existing-installation check (CLI + hosts block + timer/service)
  ↓
system information
  ↓
60-second countdown (default: cancel)
  ↓
launch by distribution
  ├─ Arch → Github520-Arch.sh install
  └─ other → github520-deploy.sh install
```

### Child script: second stage

```text
second welcome
  ↓
distribution check again
  ├─ Generic: reject Arch; WSL/Docker/Podman/LXC exit; VM warning
  └─ Arch: ID=arch only; systemd check
  ↓
root/sudo check
  ↓
existing-installation check (CLI + hosts block + timer/service; skipped by `reinstall`)
  ↓
back up original /etc/hosts
  ↓
optional Btrfs/snapper snapshot
  ↓
network backend detection
  ↓
GitHub520 download, backup and hosts update
  ↓
optional static IPv4/DNS
  ↓
validate static IP/DNS (retry or restore on failure)
  ↓
install CLI + hourly timer
  ↓
cleanup and summary
```

### Existing-installation check

`install.sh` runs a preflight before confirmation, and the child script checks again after the root check and before backing up hosts. There are three layers:

1. **CLI check**: `INSTALL_PATH`, `/usr/local/bin/<cli>`, `/usr/bin/<cli>` and the legacy `.sh` path. The CLI currently running is excluded, so the first `install` after a package install is not treated as a conflict.
2. **Hosts check**: the GitHub520 start/end markers in `/etc/hosts`; a block with no entries still counts.
3. **systemd check**: source-install units under `/etc/systemd/system`, plus whether the timer/service is enabled or active. Packaged units under `/usr/lib` or `/lib` are not treated as configured, so a freshly installed package does not produce a false conflict.

Any match prints the reason(s) and exits with status 1. No hosts backup, network change or timer installation happens in that case. `reinstall` explicitly bypasses the check for redeploying an installed CLI.

Network backend priority:

- Generic: ifupdown → NetworkManager → systemd-networkd.
- Arch: NetworkManager → systemd-networkd → ifupdown.

## Snapshots

Both scripts support:

```text
1) Snapshot all snapper configs
2) Snapshot only the @ subvolume (root config)
3) Continue without a snapshot (requires YES confirmation)
4) Abort deployment
```

Timeout, snapper error, a rejected confirmation or option 4 aborts. Option 3 continues without creating any snapshot after typing uppercase `YES` and pressing Enter within 30 seconds. For options 1/2, the snapshot is created before hosts and network changes.

If the root filesystem is not Btrfs, the scripts print a prominent `[ WARN ]` and wait for a `y/N` answer **without a timeout**. Only `y`/`yes` continues; `n` or Enter cancels the installation. A Btrfs system without snapper configs still skips snapshots automatically.

## Network configuration

- Generic: ifupdown → NetworkManager → systemd-networkd.
- Arch: NetworkManager → systemd-networkd → ifupdown.

Static changes back up the old configuration and attempt rollback on verification failure. Changing the IP or restarting an interface can interrupt SSH. An SSH session is detected from `SSH_CONNECTION`, `SSH_CLIENT`, `SSH_TTY`, the installer marker, or an ancestor process named `sshd`, `sshd-session`, `dropbear` or `mosh-server`. A bright-red warning then requires uppercase `YES` before the IP/DNS step; anything else skips that step and continues the remaining installation. This cannot guarantee SSH stays connected, so keep out-of-band access ready. If no IPv4 default route exists, static network configuration is skipped and hosts updates continue. For ifupdown only the target IPv4 stanza is rewritten; `inet6` stanzas are preserved, but IPv4 options such as MTU/bridge/bond/VLAN may be lost.

### DNS validation and recovery

After applying IP/DNS, the script validates DNS:

- first confirms the new DNS servers are actually active;
- checks DNS server reachability with `ping` when available; a missing `ping` is only a warning;
- performs a real lookup with `dig @DNS example.com`, otherwise `getent ahostsv4 example.com` or `resolvectl query`;
- tries up to 3 times, with a 2-second delay between attempts;
- on failure offers `[r]` retry, `[c]` re-enter DNS from blank and reapply, or `[a]` restore the previous network configuration;
- after restore, `[k]` keeps the restored configuration and continues installation, while `[a]` aborts;
- installs no packages; missing tools fall back to the tools that are available.

## systemd

| Item | Arch | Generic |
|---|---|---|
| Service | `github520-update.service` | `github520-deploy-update.service` |
| Timer | `github520-update.timer` | `github520-deploy-update.timer` |
| Log | `/var/log/github520/update.log` | `/var/log/github520-deploy/update.log` |

Timer behavior: first run 5 minutes after boot, then hourly. Manual updates and the timer share `/run/github520-hosts.lock`, so they never write `/etc/hosts` concurrently. Update mode does not create snapshots, change networking or reinstall the timer.

## Logs and backups

- Original hosts: `<backup-dir>/hosts.original`
- Timestamped hosts backups: `<backup-dir>/hosts.<timestamp>.<pid>` (latest 24)
- Network backups: `<backup-dir>/net-<timestamp>.<pid>/`
- Logs rotate at 1 MiB.

## Uninstall

Keep hosts/logs/backups:

```bash
sudo github520-arch --uninstall
sudo github520-deploy --uninstall
```

Complete removal:

```bash
sudo github520-arch --uninstall-completely
sudo github520-deploy --uninstall-completely
```

Complete uninstall restores the pre-install hosts, removes CLI/units, logs, backups and temp files. Use `--force` to skip confirmation.

> Manual hosts changes made after installation may be lost on complete uninstall. Back up `/etc/hosts` or use `--uninstall` if needed.

## Security

- `install.sh` requests sudo and runs as root to modify hosts, networking and systemd units.
- `bootstrap.sh` only checks the environment, selects a source and clones; it does not install packages or modify the system directly. Review it before running.
- Direct child `install` calls are rejected; installation must go through `install.sh`.
- Hosts content comes from GitHub520 and third-party mirrors. Structure and entry count are validated, but no domain allowlist is enforced.
- Downloads are HTTPS-only; redirects from HTTPS to HTTP are refused.
- Keep the installed CLI root-owned and non-writable by unprivileged users.
- Do not enable both timers on the same machine.
- Release-candidate software: keep snapshots and backups. Stable v1.0.1 is expected after RC validation.

## AI-assisted development disclosure

AI coding assistants were used while developing this project, including for drafting, code snippets and documentation editing. AI output is not published automatically; the maintainer decides what is merged, changed and released. The final version was reviewed by the maintainer and tested where feasible.

Please note:

- This project is provided **"as is"**, without warranties of any kind, express or implied, including merchantability, fitness for a particular purpose and non-infringement.
- AI-assisted material may contain errors, omissions, potential security issues, outdated information, or incompatibilities with your distribution, hardware or network setup. Review the scripts, back up your data and test in a safe environment before use.
- To the maximum extent permitted by applicable law, the author and contributors are not liable for any direct or indirect loss arising from the use, modification or distribution of this project.
- This is not an official GitHub520 project and has no affiliation, partnership or endorsement relationship with the upstream author. Rights to upstream code and hosts content remain with the original author; see [License and upstream notice](#license-and-upstream-notice) below.
- This disclosure does not change the MIT License covering this project's own code and is not legal advice.

## License and upstream notice

### This project

The scripts, `install.sh`, `bootstrap.sh` and documentation in this repository are maintained and released by **白丝小猫娘 (WS-CatGirl)** and licensed under the **MIT License**; see [LICENSE](LICENSE) for the full text.

That MIT license covers only this repository's own code and documentation. It does **not** cover the upstream GitHub520 project, its code, or its hosts content.

### Upstream GitHub520

- Upstream repository: [521xueweihan/GitHub520](https://github.com/521xueweihan/GitHub520)
- At the time of review, the upstream repository has **no `LICENSE` file**, and the GitHub API `license` field is `null`;
- The upstream project therefore must not be described as MIT-licensed or as an open-source-licensed project; rights to its code and content remain with its author;
- Obtain explicit permission from the upstream author before reusing, modifying or redistributing upstream code or content;
- This project is an independent third-party tool, **not an official GitHub520 project**, and has no affiliation, partnership or endorsement relationship with the upstream author.

### How data is obtained

This repository does not bundle upstream source code or the hosts file. The scripts only download hosts data at runtime over HTTPS from GitHub520 and third-party mirrors, then use it to update the local `/etc/hosts`.

> This is a repository-status notice, not legal advice. Confirm authorization yourself before redistribution or commercial use.

## FAQ

### 1. Which script should I use?

`install.sh` selects it automatically:

- `ID=arch`: `Github520-Arch.sh`.
- Other Linux: `github520-deploy.sh`.

### 2. Can I install both?

The paths and unit names differ, but both timers modify `/etc/hosts`. Do not enable both on the same machine.

### 3. Why do the CLIs show status instead of installing?

No arguments show status/help to prevent accidental reinstallation. Use `bash ./install.sh` from the repository; the installed CLI's `install` refuses to overwrite an existing installation, while `reinstall` explicitly bypasses that check.

### 4. `command not found`

Check `/usr/local/bin`. If sudo cannot find it, use the full path; the scripts do not modify shell profiles.

### 5. How do I refresh immediately?

```bash
sudo github520-arch update
sudo github520-deploy update
```

### 6. How do I view logs?

```bash
sudo github520-arch logs -f
sudo github520-deploy logs -f
```

### 7. Why does the generic script prefer ifupdown?

ifupdown is still common on generic Linux servers. The generic script checks ifupdown first, then NetworkManager, then systemd-networkd.

### 8. Does the generic script run in a VM?

Yes, KVM/QEMU/VMware/Hyper-V only trigger a warning. WSL/Docker/Podman/LXC exit.

### 9. Does the Arch script work in WSL/containers?

It requires systemd and `/run/systemd/system`; most WSL/container environments fail that check.

### 10. Difference between `--uninstall` and `--uninstall-completely`

- `--uninstall`: remove CLI/units, keep hosts/logs/backups.
- `--uninstall-completely`: restore hosts and remove all data.

### 11. What hosts is restored?

The script-specific `hosts.original`; otherwise the latest timestamped backup; otherwise the GitHub520 block is removed from the current file.

### 12. Will manual hosts changes survive complete uninstall?

No. Complete uninstall restores the pre-install hosts. Use `--uninstall` or back up current hosts first.

### 13. Snapshot menu timed out

Choose 1 to 4 within 30 seconds. Option 3 also requires typing uppercase `YES` and pressing Enter within 30 seconds; either timeout aborts without changing hosts or networking.

### 14. All sources failed

The script exits before modifying hosts. Check network, DNS, proxy, firewall, TLS interception and system time.

### 15. SSH disconnected after a static IP change

The current version shows a red SSH safety warning before IP/DNS changes and requires uppercase `YES`; anything else skips that step. `YES` only confirms the risk and **cannot guarantee** that SSH stays connected. Prefer a local/cloud console. If disconnected, use a console, restore from the script's `net-*` backup, restart the network backend, or restore a snapshot.

### 16. How do I reinstall/update?

To redeploy with the installed CLI:

```bash
sudo github520-arch reinstall
# or
sudo github520-deploy reinstall
```

To install a newer copy from the repository, uninstall completely first and then run the installer again:

```bash
sudo github520-arch --uninstall-completely
cd github520-deploy
bash ./install.sh
```

`install.sh` checks for an existing CLI and a GitHub520 block in `/etc/hosts` by default, and exits with an error if one is found. Only `reinstall` bypasses that check. `reinstall` uses the installed CLI and does not download a new version.

### 17. Is this stable?

No. The current version is **v1.0.1-rc** (Release Candidate). **Stable v1.0.1** is expected after RC validation. Keep backups and report issues.

### 18. Why is direct child installation rejected?

To avoid installing the wrong variant, repository copies of `Github520-Arch.sh` and `github520-deploy.sh` reject `install` unless they are launched by `install.sh`. Use:

```bash
cd github520-deploy
bash ./install.sh
```

Installed CLI commands such as `update`, `status`, `logs`, `restore` and `--uninstall` still work.

### 19. Can `install.sh` select the wrong variant?

Normally no. It reads `ID` from `/etc/os-release`: `ID=arch` selects the Arch script, everything else selects the generic script. The child script checks the platform again and exits on a mismatch.

### 20. What happens if the DNS servers are wrong?

After applying IP/DNS, the script checks DNS reachability (when `ping` is available) and performs a real lookup with `dig`, `getent` or `resolvectl`. It tries up to 3 times. On failure it offers `[r]` retry, `[c]` re-enter DNS from blank and reapply, or `[a]` restore the previous network configuration. After restore, choose `[k]` to keep it and continue installation, or `[a]` to abort.
