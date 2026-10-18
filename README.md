# GitHub520 Scripts for Linux

本仓库包含两个 GitHub520 hosts 管理脚本：

| 脚本 | 目标系统 | CLI |
|---|---|---|
| **Github520-Arch.sh** | Arch Linux（`ID=arch`） | `github520-arch` |
| **github520-deploy.sh** | 通用 Linux（systemd） | `github520-deploy` |

两者都提供：

- 猫娘风格欢迎与结束语
- root/sudo 权限处理
- Btrfs/snapper 快照
- 多源 GitHub520 下载与自动回退
- `/etc/hosts` 备份、更新与恢复
- 可选静态 IPv4/DNS
- systemd service + hourly timer
- 状态、日志、手动刷新、重装、卸载
- 原始 hosts 备份与完整卸载恢复

> 本项目不是 GitHub520 官方项目。hosts 内容来自 GitHub520 及其镜像源。
>
> 当前均为 **v0.1 beta**，请先备份并在测试机验证。

---

## 目录

- [选择哪个脚本](#选择哪个脚本)
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
- [常见问题 Q&A](#常见问题-qa)
- [English](#english)

---

## 选择哪个脚本

### 使用 `Github520-Arch.sh`，如果：

- 系统是 Arch Linux；
- 使用 NetworkManager 或 systemd-networkd；
- 希望使用 Arch 专用的 CLI 和 timer 名称。

```bash
sudo ./Github520-Arch.sh install
```

### 使用 `github520-deploy.sh`，如果：

- 系统是 Debian、Ubuntu、Fedora、CentOS、Rocky、AlmaLinux、openSUSE 等；
- 需要通用 Linux 支持；
- 更常使用 ifupdown 管理网络；
- 需要显式拒绝 WSL/Docker 容器，并对 KVM/QEMU/VMware/Hyper-V 虚拟机给出警告。

```bash
sudo ./github520-deploy.sh install
```

> **不要在同一台机器同时安装两个脚本的 timer。** 它们都会修改 `/etc/hosts`，可能互相覆盖。请只选择一个。

## 功能对比

| 项目 | Github520-Arch.sh | github520-deploy.sh |
|---|---|---|
| 系统检查 | 仅 Arch Linux（`ID=arch`） | 任意 Linux（需 systemd） |
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
- `curl`
- `ip`（iproute2）
- `findmnt`、`awk`、`sed`、`grep`、`mktemp`、`install`
- 可选：
  - Btrfs + `snapper` + `btrfs-progs`
  - NetworkManager、systemd-networkd 或 ifupdown
  - systemd-resolved / resolvconf / nscd / dnsmasq

`Github520-Arch.sh` 额外要求 `/etc/os-release` 中 `ID=arch`。

## 安装

### Arch Linux

```bash
git clone https://github.com/WS-CatGirl/github520-deploy.git
cd github520-deploy

chmod +x Github520-Arch.sh
sudo ./Github520-Arch.sh install
```

安装后：

```bash
sudo github520-arch status
sudo github520-arch update
```

### 通用 Linux

```bash
git clone https://github.com/WS-CatGirl/github520-deploy.git
cd github520-deploy

chmod +x github520-deploy.sh
sudo ./github520-deploy.sh install
```

安装后：

```bash
sudo github520-deploy status
sudo github520-deploy update
```

> 不带 `install` 参数只显示状态和简短帮助，不会安装或重装。
>
> `sudo ./Github520-Arch.sh` / `sudo ./github520-deploy.sh` 与对应 CLI 的无参数行为一致。

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

## 命令一览

以下命令对两个 CLI 都适用，只需替换命令名：

- Arch：`github520-arch`
- 通用：`github520-deploy`

| 命令 | 说明 |
|---|---|
| `sudo <cli>` | 显示状态和简短帮助 |
| `sudo <cli> install` | 交互式安装 / 重新部署 |
| `sudo <cli> reinstall` | 使用已安装版本重新部署 |
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

### 通用版 `github520-deploy.sh`

```text
欢迎 / Welcome
  ↓
root / sudo 权限检查
  ↓
Linux 检查
  ├─ WSL / Docker / Podman / LXC → 退出
  └─ KVM / QEMU / VMware / Hyper-V → 警告并继续
  ↓
首次备份原始 /etc/hosts
  ↓
Btrfs + snapper 可选快照
  ↓
网络后端检测（ifupdown 优先）
  ↓
GitHub520 源检测与下载
  ↓
备份并更新 /etc/hosts
  ↓
询问是否配置静态 IPv4 / DNS
  ↓
安装 CLI + hourly timer
  ↓
清理临时文件并输出总结
```

### Arch 版 `Github520-Arch.sh`

```text
欢迎 / Welcome
  ↓
root / sudo 权限检查
  ↓
Arch Linux 检查（ID=arch）
  ↓
首次备份原始 /etc/hosts
  ↓
Btrfs + snapper 可选快照
  ↓
网络后端检测（NetworkManager 优先）
  ↓
GitHub520 源检测与下载
  ↓
备份并更新 /etc/hosts
  ↓
询问是否配置静态 IPv4 / DNS
  ↓
安装 CLI + hourly timer
  ↓
清理临时文件并输出总结
```

## Btrfs 与 snapper 快照

两个脚本都支持：

```text
1) Snapshot all snapper configs
2) Snapshot only the @ subvolume (root config)
3) Do not snapshot (abort deployment)
```

- 30 秒实时倒计时；
- 超时、snapper/btrfs 错误或选择 3 都会中止；
- 非 Btrfs 或没有 snapper 配置时自动跳过；
- 快照发生在写 hosts 和改网络之前。

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

- ifupdown：重写目标 stanza；复杂选项（MTU、bridge、bond、VLAN、pre-up）可能丢失；
- NetworkManager：`nmcli connection modify` + reactivate；
- systemd-networkd：写 99 优先级 `.network` 文件并 reload。

修改静态 IP/DNS 会保存旧配置；验证失败时尝试回滚。

### 风险

- 修改 IP 或重启网络可能中断 SSH；
- `/etc/resolv.conf` 是符号链接时不会直接覆盖；
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

- 安装器以 root 修改 hosts、网络配置并安装 systemd unit。
- hosts 内容来自 GitHub520 及第三方 CDN/镜像；脚本校验结构和条目数量，但**没有域名白名单**。
- Timer 以 root 执行本地脚本；确保 `/usr/local/bin/github520-arch` 或 `/usr/local/bin/github520-deploy` 归 root 所有且不可被普通用户写入。
- 脚本不会安装软件包、修改防火墙或 SSH 配置。
- 两个脚本的 timer 不应当同时启用。
- 当前为 **v0.1 beta**，请保留快照和备份。

## 常见问题 Q&A

### Q1: 应该选哪个脚本？

- Arch Linux：`Github520-Arch.sh`；
- 其他 Linux：`github520-deploy.sh`。

### Q2: 两个脚本可以同时安装吗？

技术上安装路径和 unit 名称不同，但两个 timer 都会改 `/etc/hosts`，会互相覆盖。**不要同时启用两个 timer**，只选一个。

### Q3: 为什么 `sudo github520-arch` / `sudo github520-deploy` 显示状态而不是安装？

为了防止误重装。安装使用：

```bash
sudo github520-arch install
sudo github520-deploy install
```

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

30 秒内必须选择 1 或 2；选择 3 会主动中止。

### Q14: 所有 GitHub520 源都失败？

脚本会在修改 hosts 前退出。检查网络、DNS、代理、防火墙、TLS 拦截和系统时间。

### Q15: 静态 IP 修改后 SSH 断线？

使用本地/云控制台，查看对应 `/var/backups/github520*` 的 `net-*` 目录，恢复配置并重启网络后端，或恢复快照。

### Q16: 如何重装/更新脚本？

从仓库重新运行安装：

```bash
sudo ./Github520-Arch.sh install
sudo ./github520-deploy.sh install
```

`reinstall` 只使用已安装 CLI 重新部署，不会从网络下载新版本。

### Q17: 这是正式版吗？

不是。两个脚本均为 **v0.1 beta**，请先备份并反馈问题。

---

# English

This repository contains two GitHub520 hosts managers:

| Script | Target | CLI |
|---|---|---|
| **Github520-Arch.sh** | Arch Linux (`ID=arch`) | `github520-arch` |
| **github520-deploy.sh** | Generic Linux (systemd) | `github520-deploy` |

Both provide:

- Catgirl-style welcome and final message
- root/sudo handling
- Btrfs/snapper snapshots
- Multiple GitHub520 sources with fallback
- `/etc/hosts` backup, update and restore
- Optional static IPv4/DNS
- systemd service + hourly timer
- status, logs, manual refresh, reinstall and uninstall
- original hosts backup and complete-uninstall restore

> This is not an official GitHub520 project. Both scripts are **v0.1 beta**.

## Which script?

Use `Github520-Arch.sh` on Arch Linux. Use `github520-deploy.sh` on other Linux distributions, especially systems using ifupdown.

Do **not** enable both timers on the same machine; both modify `/etc/hosts`.

## Comparison

| Item | Github520-Arch.sh | github520-deploy.sh |
|---|---|---|
| OS check | Arch only (`ID=arch`) | Any Linux with systemd |
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
- `curl`, `ip`, `findmnt`, `awk`, `sed`, `grep`, `mktemp`, `install`
- Optional: Btrfs + snapper + btrfs-progs
- Optional: NetworkManager, systemd-networkd, ifupdown
- Optional: systemd-resolved, resolvconf, nscd or dnsmasq

## Install

### Arch

```bash
chmod +x Github520-Arch.sh
sudo ./Github520-Arch.sh install
```

### Generic

```bash
chmod +x github520-deploy.sh
sudo ./github520-deploy.sh install
```

Running without `install` only shows status/help.

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

## Commands

Replace `<cli>` with `github520-arch` or `github520-deploy`:

| Command | Description |
|---|---|
| `sudo <cli>` | Status and short help |
| `sudo <cli> install` | Interactive install/redeploy |
| `sudo <cli> reinstall` | Redeploy using the installed CLI |
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

### Generic

1. Welcome.
2. Root/sudo check.
3. Linux check:
   - WSL/Docker/Podman/LXC → exit;
   - KVM/QEMU/VMware/Hyper-V → warn and continue.
4. Back up original `/etc/hosts` (first install).
5. Optional Btrfs/snapper snapshot.
6. Network backend detection (ifupdown first).
7. GitHub520 source check/download.
8. Update `/etc/hosts`.
9. Optional static IPv4/DNS.
10. Install CLI + hourly timer.
11. Cleanup and summary.

### Arch

1. Welcome.
2. Root/sudo check.
3. Arch Linux check.
4. Back up original hosts.
5. Optional snapshot.
6. Network backend detection (NetworkManager first).
7. GitHub520 download/update.
8. Optional static IPv4/DNS.
9. Install CLI + hourly timer.
10. Cleanup and summary.

## Snapshots

Both scripts support:

```text
1) Snapshot all snapper configs
2) Snapshot only the @ subvolume (root config)
3) Do not snapshot (abort deployment)
```

Timeout, snapper error or option 3 aborts.

## Network configuration

- Generic: ifupdown → NetworkManager → systemd-networkd.
- Arch: NetworkManager → systemd-networkd → ifupdown.

Static changes back up the old configuration and attempt rollback on verification failure. Changing the IP or restarting an interface can interrupt SSH. Complex ifupdown options such as MTU/bridge/bond/VLAN may be lost.

## systemd

| Item | Arch | Generic |
|---|---|---|
| Service | `github520-update.service` | `github520-deploy-update.service` |
| Timer | `github520-update.timer` | `github520-deploy-update.timer` |
| Log | `/var/log/github520/update.log` | `/var/log/github520-deploy/update.log` |

Timer behavior: first run 5 minutes after boot, then hourly. Update mode does not create snapshots, change networking or reinstall the timer.

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

- Installers run as root and modify system files, networking and systemd units.
- Hosts content comes from GitHub520 and third-party mirrors. Structure and entry count are validated, but no domain allowlist is enforced.
- Keep the installed CLI root-owned and non-writable by unprivileged users.
- Do not enable both timers on the same machine.
- Beta software: keep snapshots and backups.

## FAQ

### 1. Which script should I use?

- Arch Linux: `Github520-Arch.sh`.
- Other Linux: `github520-deploy.sh`.

### 2. Can I install both?

The paths and unit names differ, but both timers modify `/etc/hosts`. Do not enable both on the same machine.

### 3. Why do the CLIs show status instead of installing?

No arguments show status/help to prevent accidental reinstallation. Use `install`.

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

Choose 1 or 2 within 30 seconds. Option 3 aborts.

### 14. All sources failed

The script exits before modifying hosts. Check network, DNS, proxy, firewall, TLS interception and system time.

### 15. SSH disconnected after a static IP change

Use a local/cloud console, restore from the script's `net-*` backup, restart the network backend, or restore a snapshot.

### 16. How do I reinstall/update?

Run the repository installer again:

```bash
sudo ./Github520-Arch.sh install
sudo ./github520-deploy.sh install
```

`reinstall` only redeploys the installed CLI; it does not download a new version.

### 17. Is this stable?

No. Both scripts are **v0.1 beta**. Keep backups and report issues.
