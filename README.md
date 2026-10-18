# GitHub520-Arch

面向 **Arch Linux** 的 GitHub520 管理器（Beta）。

- 当前版本：**v0.1 (beta)**
- 作者：**白丝小猫娘 (WS-CatGirl)**
- 源码：[Github520-Arch.sh](Github520-Arch.sh)
- 旧版通用脚本：[github520-deploy.sh](github520-deploy.sh)（仍保留，但本 README 主要介绍 Arch 版）

> 本项目不是 GitHub520 官方项目。hosts 内容来自 GitHub520 及其镜像源。
>
> Beta 版本请先在测试机或快照中验证，并保留备份。

---

## 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [安装](#安装)
- [PATH 与命令](#path-与命令)
- [命令一览](#命令一览)
- [安装流程](#安装流程)
- [Btrfs 与 snapper 快照](#btrfs-与-snapper-快照)
- [网络检测与静态 IP/DNS](#网络检测与静态-ipdns)
- [systemd timer 与 service](#systemd-timer-与-service)
- [日志与备份](#日志与备份)
- [卸载](#卸载)
- [安全说明](#安全说明)
- [常见问题 Q&A](#常见问题-qa)
- [English](#english)

---

## 功能特性

- 安装为无扩展名可执行 CLI：`/usr/local/bin/github520-arch`
- 在任意目录（包括 `/home`）直接使用 `sudo github520-arch`，不需要 `cd` 到项目目录
- 无参数时显示状态与命令提示，不直接重装
- 支持立即手动刷新 hosts
- 支持状态、日志、备份恢复、重新安装、卸载
- 优先检测 NetworkManager，同时支持 systemd-networkd、ifupdown
- Btrfs + snapper 快照，30 秒倒计时
- 内置多个 GitHub520 源，失败自动切换
- 每小时自动更新 hosts
- 更新成功/失败写入 `/var/log/github520/update.log`
- 安装前保存原始 hosts，`--uninstall-completely` 可恢复
- 猫娘风格欢迎与结束语

## 系统要求

- **Arch Linux**（`/etc/os-release` 中 `ID=arch`）
- systemd
- bash 4+
- `curl`
- `ip`（iproute2）
- `findmnt`、`awk`、`sed`、`grep`、`mktemp`、`install` 等工具
- 可选：
  - Btrfs + `snapper` + `btrfs-progs`
  - NetworkManager（推荐）
  - systemd-networkd 或 ifupdown（备用静态配置后端）
  - systemd-resolved / resolvconf / nscd / dnsmasq

## 安装

```bash
git clone https://github.com/WS-CatGirl/github520-deploy.git
cd github520-deploy

chmod +x Github520-Arch.sh
sudo ./Github520-Arch.sh install
```

安装器会：

1. 显示猫娘欢迎界面；
2. 检查 root/sudo；
3. 检查 Arch Linux；
4. 可选创建 Btrfs/snapper 快照；
5. 检测网络后端；
6. 下载并更新 `/etc/hosts`；
7. 可选配置静态 IPv4/DNS；
8. 安装 `/usr/local/bin/github520-arch`；
9. 安装并启用 `github520-update.timer`；
10. 清理临时文件并输出总结。

安装完成后可以直接：

```bash
sudo github520-arch status
sudo github520-arch update
sudo github520-arch logs
```

> 不带 `install` 参数时**不会安装**，只显示状态和帮助提示。
>
> `sudo ./Github520-Arch.sh` 与 `sudo github520-arch` 的行为一致。

## PATH 与命令

脚本安装到：

```text
/usr/local/bin/github520-arch
```

`/usr/local/bin` 是 Arch Linux 的标准 PATH 目录，通常也在 sudo 的 `secure_path` 中，因此：

```bash
cd /home
sudo github520-arch status
```

可以直接执行，不需要位于项目目录。

如果某些 sudo 配置没有包含 `/usr/local/bin`，可以使用完整路径：

```bash
sudo /usr/local/bin/github520-arch status
```

脚本**不会修改** `/etc/profile` 或用户的 `.bashrc`。依赖标准的 `/usr/local/bin`，避免污染 PATH。

同时会创建兼容入口：

```text
/usr/local/bin/github520-arch.sh -> /usr/local/bin/github520-arch
```

## 命令一览

| 命令 | 说明 |
|---|---|
| `sudo github520-arch` | 显示状态和简短帮助 |
| `sudo github520-arch install` | 交互式安装 / 重新部署 |
| `sudo github520-arch reinstall` | 同 `install`，使用已安装版本重新部署 |
| `sudo github520-arch update` | 立即拉取并刷新 hosts |
| `sudo github520-arch refresh` | `update` 的别名 |
| `sudo github520-arch status` | 显示版本、hosts 条目、timer、最近日志、备份数量 |
| `sudo github520-arch logs` | 查看更新日志 |
| `sudo github520-arch logs -f` | 实时跟踪日志 |
| `sudo github520-arch restore` | 恢复最近一份 hosts 备份 |
| `sudo github520-arch restore original` | 恢复安装前保存的原始 hosts |
| `sudo github520-arch restore /path/to/hosts` | 恢复指定备份 |
| `sudo github520-arch --uninstall` | 卸载 CLI 和 systemd unit，**保留** hosts、日志、备份 |
| `sudo github520-arch --uninstall-completely` | 恢复原始 hosts，并删除 CLI、unit、日志、备份和临时文件 |
| `sudo github520-arch --uninstall-completely --force` | 跳过完整卸载确认 |
| `github520-arch version` | 显示版本 |
| `github520-arch help` | 显示帮助 |

内部的 systemd 模式：

```bash
/usr/local/bin/github520-arch --update --systemd
```

该模式由 timer 调用，会把全部输出写入 `/var/log/github520/update.log`，不需要手动执行。

## 安装流程

```text
欢迎 / Welcome
  ↓
权限检查（root / sudo）
  ↓
Arch Linux 检查
  ↓
备份原始 /etc/hosts（仅首次）
  ↓
Btrfs + snapper 可选快照
  ↓
网络后端检测（NetworkManager 优先）
  ↓
GitHub520 源检测与下载
  ↓
更新 /etc/hosts
  ↓
询问是否配置静态 IPv4 / DNS
  ↓
安装 CLI + hourly timer
  ↓
清理临时文件并输出总结
```

### 原始 hosts 备份

安装器在首次修改 hosts 前保存：

```text
/var/backups/github520/hosts.original
```

- 只在文件不存在时创建，不会被后续安装覆盖；
- `--uninstall-completely` 会优先恢复它；
- 如果没有 original，则使用最近的时间戳备份；
- 如果都没有，则直接从当前 hosts 删除 GitHub520 块。

### 时间戳备份

每次 hosts 内容变化前创建：

```text
/var/backups/github520/hosts.<YYYYmmdd-HHMMSS>.<pid>
```

默认保留最近 24 份；`hosts.original` 不计入轮转。

## Btrfs 与 snapper 快照

当根文件系统是 Btrfs，且 snapper 有配置时：

```text
1) Snapshot all snapper configs
2) Snapshot only the @ subvolume (root config)
3) Do not snapshot (abort deployment)
```

- 30 秒倒计时；
- 超时、snapper/btrfs 错误或选择 3 都会中止；
- 非 Btrfs 或没有 snapper 配置会自动跳过；
- 快照发生在写 hosts 和修改网络之前。

## 网络检测与静态 IP/DNS

检测顺序：

1. **NetworkManager（优先）**
2. systemd-networkd
3. ifupdown
4. dhcpcd / ConnMan / iwd / netctl（只检测）

静态配置后端：

- NetworkManager：`nmcli connection modify` 设置 manual、地址、网关、DNS；
- systemd-networkd：写入 `/etc/systemd/network/99-github520-<iface>.network`；
- ifupdown：重写目标接口 stanza；
- 没有可用后端：报错退出。

静态修改会保存旧配置，并在验证失败时尝试回滚。

### 风险

- 修改 IP 或重启网络可能中断 SSH；
- ifupdown 复杂配置（MTU、bridge、bond、VLAN、pre-up 等）可能丢失；
- `/etc/resolv.conf` 是符号链接时不会直接覆盖；
- 优先使用本地控制台或云控制台操作。

## systemd timer 与 service

安装路径：

```text
/usr/local/bin/github520-arch
```

Service：

```text
/etc/systemd/system/github520-update.service
```

核心配置：

```ini
[Service]
Type=oneshot
ExecStart=/usr/local/bin/github520-arch --update --systemd
```

Timer：

```text
/etc/systemd/system/github520-update.timer
```

```ini
[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
AccuracySec=1min
RandomizedDelaySec=30s
Persistent=true
Unit=github520-update.service
```

行为：

- 安装完成后立即执行一次 hosts 更新；
- 开机 5 分钟后首次 timer 运行；
- 之后每小时运行一次；
- 更新成功/失败写入日志；
- 更新模式不创建快照、不改网络、不重装 timer。

常用命令：

```bash
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
systemctl start github520-update.service
journalctl -u github520-update.service
tail -f /var/log/github520/update.log
```

## 日志与备份

### 更新日志

```text
/var/log/github520/update.log
```

包含：

- 开始/结束时间；
- 使用的源；
- 成功或失败；
- 失败原因；
- 手动更新的摘要。

超过 1 MiB 时轮转为 `update.log.1`。

### hosts 备份

```text
/var/backups/github520/hosts.original
/var/backups/github520/hosts.<时间>.<pid>
```

### 网络备份

```text
/var/backups/github520/net-<时间>.<pid>/
```

### 临时文件

安装/更新使用的 `mktemp` 目录会在退出或安装结束时删除。

## 卸载

### 保留数据卸载

```bash
sudo github520-arch --uninstall
```

会：

- 停止并禁用 `github520-update.timer`；
- 删除 service/timer unit；
- 删除 `/usr/local/bin/github520-arch` 和兼容入口；
- **保留** `/etc/hosts`、日志、备份。

适合以后还要重新安装，或想手动检查残留配置的情况。

### 完全卸载

```bash
sudo github520-arch --uninstall-completely
```

会：

1. 停止并删除 systemd units；
2. 恢复 `hosts.original`（不存在则用最近备份）；
3. 从恢复后的 hosts 中移除 GitHub520 块；
4. 删除 CLI、兼容入口；
5. 删除 `/var/log/github520`；
6. 删除 `/var/backups/github520`；
7. 删除 `/etc/hosts.github520-backup.*` 旧备份；
8. 清理 `/tmp/github520-arch*` 等临时文件。

完整卸载会要求确认；自动化可加 `--force`：

```bash
sudo github520-arch --uninstall-completely --force
```

> 完整卸载会恢复**首次安装前**的 hosts，因此安装后手动添加的其他 hosts 修改也可能丢失。
>
> 如需保留安装后的手动修改，请使用 `--uninstall`，或先手动备份当前 `/etc/hosts`。

## 安全说明

- 安装器以 root 修改 hosts、网络配置并安装 systemd unit。
- hosts 内容来自 GitHub520 及第三方 CDN/镜像；脚本校验结构和条目数量，但**没有域名白名单**。镜像被劫持时可能写入恶意解析记录。
- Timer 以 root 执行本地脚本；确保 `/usr/local/bin/github520-arch` 归 root 所有且不可被普通用户写入。
- 脚本不会安装软件包、修改防火墙或 SSH 配置。
- 这是 **v0.1 beta**，请保留快照和备份。

## 常见问题 Q&A

### Q1: 为什么 `sudo github520-arch` 显示状态而不是安装？

这是设计行为。无参数只显示状态和帮助提示，避免误重装。安装使用：

```bash
sudo github520-arch install
```

### Q2: `sudo github520-arch` 提示 command not found？

先确认 CLI 是否存在：

```bash
ls -l /usr/local/bin/github520-arch
```

如果存在但 sudo 找不到，使用完整路径：

```bash
sudo /usr/local/bin/github520-arch status
```

脚本不会修改 `/etc/profile` 或 `.bashrc`；`/usr/local/bin` 是标准 PATH 目录。部分自定义 sudoers 的 `secure_path` 可能不包含它。

### Q3: 如何立即刷新 hosts，不等下一次 timer？

```bash
sudo github520-arch update
```

成功/失败会显示在终端，并追加到更新日志。

### Q4: 如何查看日志？

```bash
sudo github520-arch logs
sudo github520-arch logs -f
```

或：

```bash
tail -f /var/log/github520/update.log
```

### Q5: timer 没有运行？

检查：

```bash
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
systemctl status github520-update.service
journalctl -u github520-update.service
```

常见原因：

- systemd 不是 PID 1；
- timer 被 disable；
- `/usr/local/bin/github520-arch` 被删除；
- unit 修改后未 `daemon-reload`。

### Q6: 如何重新安装/更新脚本？

如果修改了仓库中的脚本，重新运行仓库安装器：

```bash
sudo ./Github520-Arch.sh install
```

`sudo github520-arch reinstall` 只会使用**已安装的 CLI**重新部署，不会从网络拉取新版本。

### Q7: `--uninstall` 和 `--uninstall-completely` 有什么区别？

- `--uninstall`：删除 CLI 和 systemd unit，保留 hosts、日志、备份；
- `--uninstall-completely`：恢复原始 hosts，并删除 CLI、unit、日志、备份和临时文件。

### Q8: 完整卸载会恢复什么 hosts？

优先恢复：

```text
/var/backups/github520/hosts.original
```

这是首次安装前保存的原始 hosts。若不存在，则使用最近的时间戳备份。若都没有，则直接从当前 hosts 删除 GitHub520 块。

### Q9: 安装后手动改过 hosts，完整卸载会保留吗？

不会。完整卸载以原始 hosts 为基准，安装后的手动修改可能丢失。请先手动备份当前 `/etc/hosts`，或使用 `--uninstall` 保留 hosts。

### Q10: 为什么提示只支持 Arch Linux？

脚本检查 `/etc/os-release` 的 `ID=arch`。Manjaro、EndeavourOS 等 Arch 衍生版会被拒绝。

### Q11: Arch WSL/容器能用吗？

需要 systemd 和 `/run/systemd/system`。大多数 WSL/容器不满足，会在检查阶段退出。不要在隔离环境中修改宿主机网络。

### Q12: 快照菜单超时了？

30 秒内必须选择 1 或 2；选择 3 会主动中止。重新运行并尽快选择。

### Q13: 所有 GitHub520 源都失败？

脚本会在修改 hosts 前退出。检查网络、DNS、代理、防火墙、TLS 拦截和系统时间。

### Q14: 静态 IP 修改后 SSH 断线？

使用本地/云控制台登录，查看 `/var/backups/github520/net-*`，恢复配置并重启 NetworkManager/systemd-networkd/ifupdown，或恢复快照。

### Q15: 如何恢复 hosts 备份？

```bash
sudo github520-arch restore
sudo github520-arch restore original
sudo github520-arch restore /var/backups/github520/hosts.20260101-120000.1234
```

### Q16: 这是正式版吗？

不是。当前是 **v0.1 beta**，请先备份并反馈问题。

---

# English

GitHub520 hosts manager for **Arch Linux** (Beta).

- Version: **v0.1 (beta)**
- Author: **白丝小猫娘 (WS-CatGirl)**
- Source: [Github520-Arch.sh](Github520-Arch.sh)
- Legacy generic script: [github520-deploy.sh](github520-deploy.sh)

> This is not an official GitHub520 project. Beta software: keep backups and test before production use.

## Features

- Installs an extensionless executable CLI at `/usr/local/bin/github520-arch`.
- Run it from any directory, including `/home`, with `sudo github520-arch`.
- No arguments show status and a short help hint instead of reinstalling.
- Immediate manual refresh, status, logs, restore, reinstall and uninstall.
- NetworkManager first, then systemd-networkd/ifupdown.
- Optional Btrfs/snapper snapshot with a 30-second countdown.
- Multiple GitHub520 sources with fallback.
- Hourly systemd timer.
- Update success/failure logged to `/var/log/github520/update.log`.
- Original `/etc/hosts` saved before the first modification.
- Catgirl-style welcome and final message.

## Requirements

- Arch Linux (`ID=arch`)
- systemd
- bash 4+
- `curl`, `ip`, `findmnt`, `awk`, `sed`, `grep`, `mktemp`, `install`
- Optional: Btrfs + snapper + btrfs-progs
- Optional: NetworkManager, systemd-networkd, ifupdown
- Optional: systemd-resolved, resolvconf, nscd or dnsmasq

## Install

```bash
git clone https://github.com/WS-CatGirl/github520-deploy.git
cd github520-deploy

chmod +x Github520-Arch.sh
sudo ./Github520-Arch.sh install
```

The installer:

1. shows the welcome screen;
2. checks root/sudo;
3. checks Arch Linux;
4. optionally creates a snapshot;
5. detects the network backend;
6. downloads and updates `/etc/hosts`;
7. optionally configures static IPv4/DNS;
8. installs `/usr/local/bin/github520-arch`;
9. installs and enables `github520-update.timer`;
10. cleans temporary files and prints a summary.

Running without `install` only shows status/help; it does not install.

## PATH

The CLI is installed at:

```text
/usr/local/bin/github520-arch
```

`/usr/local/bin` is a standard PATH directory and is normally included in sudo's `secure_path`, so this works from any directory:

```bash
cd /home
sudo github520-arch status
```

If your sudo configuration does not include it:

```bash
sudo /usr/local/bin/github520-arch status
```

The script does **not** modify `/etc/profile` or `.bashrc`.

A compatibility symlink is created:

```text
/usr/local/bin/github520-arch.sh -> /usr/local/bin/github520-arch
```

## Commands

| Command | Description |
|---|---|
| `sudo github520-arch` | Show status and a short help hint |
| `sudo github520-arch install` | Interactive install / redeploy |
| `sudo github520-arch reinstall` | Re-run the installer using the installed CLI |
| `sudo github520-arch update` | Immediately refresh hosts |
| `sudo github520-arch refresh` | Alias for update |
| `sudo github520-arch status` | Show version, hosts entries, timer, last log, backups |
| `sudo github520-arch logs` | Show update log |
| `sudo github520-arch logs -f` | Follow update log |
| `sudo github520-arch restore` | Restore the latest hosts backup |
| `sudo github520-arch restore original` | Restore the pre-install hosts |
| `sudo github520-arch restore FILE` | Restore a specific backup |
| `sudo github520-arch --uninstall` | Remove CLI/units, keep hosts/logs/backups |
| `sudo github520-arch --uninstall-completely` | Restore hosts and remove all data |
| `sudo github520-arch --uninstall-completely --force` | Skip the complete-uninstall confirmation |
| `github520-arch version` | Show version |
| `github520-arch help` | Show help |

Internal timer mode:

```bash
/usr/local/bin/github520-arch --update --systemd
```

## Install flow

1. Welcome.
2. Root/sudo check.
3. Arch Linux check.
4. Save original `/etc/hosts` (first install only).
5. Optional Btrfs/snapper snapshot.
6. Network backend detection (NetworkManager first).
7. GitHub520 source check and download.
8. Update `/etc/hosts`.
9. Optional static IPv4/DNS.
10. Install CLI and hourly timer.
11. Cleanup and summary.

## Snapshots

On Btrfs with snapper:

```text
1) Snapshot all snapper configs
2) Snapshot only the @ subvolume (root config)
3) Do not snapshot (abort deployment)
```

Timeout, snapper error or option 3 aborts. Non-Btrfs systems and systems without snapper configs skip this step.

## Network configuration

Priority:

1. NetworkManager
2. systemd-networkd
3. ifupdown

Static configuration uses `nmcli`, systemd-networkd `.network` files, or an ifupdown stanza rewrite. DNS uses systemd-resolved, resolvconf, or a direct `/etc/resolv.conf` write (symlinks are not overwritten).

Changing the IP or restarting an interface can interrupt SSH. Use a local/out-of-band console. Complex ifupdown options such as MTU/bridge/bond/VLAN may be lost.

## systemd timer and service

Installed CLI:

```text
/usr/local/bin/github520-arch
```

Units:

```text
/etc/systemd/system/github520-update.service
/etc/systemd/system/github520-update.timer
```

Service:

```ini
[Service]
Type=oneshot
ExecStart=/usr/local/bin/github520-arch --update --systemd
```

Timer:

```ini
OnBootSec=5min
OnUnitActiveSec=1h
AccuracySec=1min
RandomizedDelaySec=30s
Persistent=true
```

Commands:

```bash
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
systemctl start github520-update.service
journalctl -u github520-update.service
tail -f /var/log/github520/update.log
```

## Logs and backups

- Update log: `/var/log/github520/update.log` (rotated at 1 MiB).
- Original hosts: `/var/backups/github520/hosts.original`.
- Timestamped backups: `/var/backups/github520/hosts.<timestamp>.<pid>` (latest 24).
- Network backups: `/var/backups/github520/net-<timestamp>.<pid>/`.

## Uninstall

### Keep data

```bash
sudo github520-arch --uninstall
```

Removes the CLI and systemd units, but keeps `/etc/hosts`, logs and backups.

### Complete removal

```bash
sudo github520-arch --uninstall-completely
```

Stops/removes units, restores `hosts.original` (or the latest backup), removes GitHub520 entries, deletes the CLI, logs, backups and temporary files.

Use `--force` to skip confirmation:

```bash
sudo github520-arch --uninstall-completely --force
```

> Complete uninstall restores the hosts file from before the first installation. Manual hosts changes made after installation may be lost. Use `--uninstall` or back up the current `/etc/hosts` first.

## Security

- The installer runs as root and modifies hosts, network settings and systemd units.
- Hosts content comes from GitHub520 and third-party CDNs/mirrors. Structure and entry count are validated, but no domain allowlist is enforced.
- The timer executes a root-owned local script. Keep `/usr/local/bin/github520-arch` root-owned and non-writable by unprivileged users.
- No packages, firewall rules or SSH configuration are modified.
- Beta software: keep snapshots and backups.

## FAQ

### 1. Why does `sudo github520-arch` show status instead of installing?

That is intentional to prevent accidental reinstallation. Use `sudo github520-arch install`.

### 2. `github520-arch: command not found`

Check:

```bash
ls -l /usr/local/bin/github520-arch
```

If it exists but sudo cannot find it, use the full path:

```bash
sudo /usr/local/bin/github520-arch status
```

The script does not modify `/etc/profile` or `.bashrc`; some custom sudoers `secure_path` settings may exclude `/usr/local/bin`.

### 3. How do I refresh immediately?

```bash
sudo github520-arch update
```

### 4. How do I view logs?

```bash
sudo github520-arch logs
sudo github520-arch logs -f
```

### 5. The timer is not running

Check:

```bash
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
journalctl -u github520-update.service
```

### 6. How do I reinstall or update the script?

Run the repository installer:

```bash
sudo ./Github520-Arch.sh install
```

`github520-arch reinstall` only redeploys the currently installed CLI; it does not download a new version.

### 7. Difference between `--uninstall` and `--uninstall-completely`

- `--uninstall`: remove CLI/units; keep hosts, logs and backups.
- `--uninstall-completely`: restore hosts and remove CLI/units/logs/backups/temp files.

### 8. What hosts file is restored on complete uninstall?

`/var/backups/github520/hosts.original` first; otherwise the latest timestamped backup; otherwise the GitHub520 block is removed from the current file.

### 9. Will manual hosts changes survive complete uninstall?

No. Complete uninstall restores the pre-install hosts. Back up current `/etc/hosts` or use `--uninstall` if you need to keep manual changes.

### 10. Why only Arch Linux?

The script checks `ID=arch` in `/etc/os-release`. Manjaro, EndeavourOS and other derivatives are rejected.

### 11. Does it work in Arch WSL/containers?

It requires systemd and `/run/systemd/system`; most WSL/container setups fail this check. Do not modify host networking from an isolated environment.

### 12. Snapshot menu timed out

Choose 1 or 2 within 30 seconds. Option 3 aborts.

### 13. All sources failed

The script exits before modifying hosts. Check network, DNS, proxy, firewall, TLS interception and system time.

### 14. SSH disconnected after a static IP change

Use a local/cloud console, restore from `/var/backups/github520/net-*`, restart the network backend, or restore a snapshot.

### 15. How do I restore hosts?

```bash
sudo github520-arch restore
sudo github520-arch restore original
sudo github520-arch restore /var/backups/github520/hosts.20260101-120000.1234
```

### 16. Is this stable?

No. This is **v0.1 beta**. Keep backups and report issues.
