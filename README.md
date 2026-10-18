# GitHub520-Arch

面向 **Arch Linux** 的 GitHub520 hosts 安装器（Beta）。

- 当前版本：**v0.1 (beta)**
- 作者：**白丝小猫娘 (WS-CatGirl)**
- 新脚本：[Github520-Arch.sh](Github520-Arch.sh)
- 旧版通用脚本：[github520-deploy.sh](github520-deploy.sh)（仍然保留，本 README 主要介绍 Arch 版）

> 本项目不是 GitHub520 官方项目。hosts 内容来自 GitHub520 及其镜像源。
>
> Beta 版本可能调整行为，重要机器请先做快照或手动备份。

---

## 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [命令行参数](#命令行参数)
- [安装流程](#安装流程)
- [Btrfs 与 snapper 快照](#btrfs-与-snapper-快照)
- [网络检测与静态 IP/DNS](#网络检测与静态-ipdns)
- [systemd timer 与 service](#systemd-timer-与-service)
- [日志与备份](#日志与备份)
- [更新、卸载与还原](#更新卸载与还原)
- [安全说明](#安全说明)
- [常见问题 Q&A](#常见问题-qa)
- [English](#english)

---

## 功能特性

- 猫娘风格欢迎界面，当前版本 **v0.1 beta**。
- 仅支持 **Arch Linux**（`/etc/os-release` 中 `ID=arch`）；Manjaro、EndeavourOS 等 Arch 衍生版会被拒绝。
- 自动处理 root/sudo：
  - root 直接运行；
  - 普通用户有 sudo 时自动提权；
  - 没有 sudo 或认证失败会给出访问拒绝提示。
- Btrfs + snapper 环境支持创建快照，30 秒倒计时菜单。
- 优先检测 **NetworkManager**，同时识别 systemd-networkd、ifupdown、dhcpcd、ConnMan、iwd、netctl。
- 内置多个 GitHub520 源，单个源失败会自动切换。
- 写入 `/etc/hosts` 前备份；写入失败或校验失败自动恢复。
- 可选配置静态 IPv4、网关和 DNS；支持 NetworkManager、systemd-networkd、ifupdown。
- 安装 systemd service + timer，**每小时自动更新 hosts**。
- 自动更新成功或失败都会写入 `/var/log/github520/update.log`。
- 运行提示以英文为主，欢迎和结尾使用双语猫娘风格；避免在 TTY 中出现大段中文乱码。

## 系统要求

- **Arch Linux**（仅 `ID=arch`）
- systemd（用于安装 timer/service）
- bash 4+
- `curl`
- `ip`（iproute2）
- `findmnt`、`awk`、`sed`、`grep`、`mktemp`、`install` 等 coreutils/util-linux 工具
- 可选：
  - Btrfs 根文件系统 + `snapper` + `btrfs-progs`
  - NetworkManager（推荐）
  - systemd-networkd 或 ifupdown（备用静态配置后端）
  - systemd-resolved / resolvconf / nscd / dnsmasq（DNS 生效和缓存刷新）

## 快速开始

```bash
git clone https://github.com/WS-CatGirl/github520-deploy.git
cd github520-deploy

chmod +x Github520-Arch.sh
sudo ./Github520-Arch.sh
```

也可以普通用户直接运行，脚本会请求 sudo：

```bash
./Github520-Arch.sh
```

查看帮助或版本：

```bash
./Github520-Arch.sh --help
./Github520-Arch.sh --version
```

## 命令行参数

| 参数 | 说明 |
|---|---|
| `-h`, `--help` | 显示帮助并退出，不需要 root。 |
| `-V`, `--version` | 显示版本并退出。 |
| `--update` | systemd timer 使用的内部模式：非交互更新 hosts，写入日志后退出。普通用户不需要手动使用。 |

正常安装不建议使用 `--update`；它会跳过欢迎、快照、网络配置和 timer 安装。

## 安装流程

```text
欢迎 / Welcome
  ↓
权限检查（root / sudo）
  ↓
Arch Linux 检查
  ↓
Btrfs + snapper 可选快照
  ↓
网络后端检测（NetworkManager 优先）
  ↓
GitHub520 源检测
  ↓
备份并更新 /etc/hosts
  ↓
询问是否配置静态 IPv4 / DNS
  ↓
安装并启用 hourly timer
  ↓
清理临时文件，输出总结
```

### 1. 欢迎

显示猫娘风格欢迎语、`Ciallo～(∠・ω< )⌒★` 和版本 `v0.1 beta`。

### 2. 权限

- root：直接继续。
- 普通用户：
  - 有可用 sudo：自动重新执行；
  - 需要密码：调用 `sudo -v` 请求验证；
  - 无 sudo 或验证失败：输出 `ACCESS DENIED` 并退出。

### 3. Arch 检查

读取 `/etc/os-release`：

```bash
ID=arch
```

不是 Arch Linux 会立即退出，不会修改任何文件。

### 4. 快照

仅当根文件系统是 Btrfs 且 snapper 有配置时询问。详见下文。

### 5. 网络检测

先检测 NetworkManager，再检测 systemd-networkd、ifupdown、dhcpcd、ConnMan、iwd、netctl，并读取默认路由、接口、网关和当前 IP。

### 6. GitHub520 更新

- 逐个探测内置源；
- 下载并校验 `# GitHub520 Host Start/End`、条目数量；
- 失败自动切换下一个源；
- 全部失败则退出，不修改 hosts。

### 7. 写入 hosts

- 备份到 `/var/backups/github520/hosts.<时间>.<pid>`；
- 删除旧 GitHub520 块；
- 去除末尾多余空行，追加新块；
- 写入 `/etc/hosts` 并验证；
- 失败时自动恢复备份；
- 刷新 DNS 缓存。

### 8. 静态 IP/DNS（可选）

询问：

```text
Change the local static IPv4 address / DNS now? [y/N]:
```

选 `y` 后会显示当前接口、地址、网关，并询问：

- 静态 IPv4（CIDR，例如 `192.168.1.50/24`）
- DNS1
- DNS2（可留空）

然后再次确认并应用。具体后端见下文。

### 9. timer/service

安装并启用：

- `/etc/systemd/system/github520-update.service`
- `/etc/systemd/system/github520-update.timer`

### 10. 收尾

清理临时目录，输出仓库地址、作者、timer 和日志命令，并附猫娘风格结束语。

## Btrfs 与 snapper 快照

当根文件系统是 Btrfs，且 `snapper` 已安装并有配置时：

1. 执行 `snapper list-configs`；
2. 执行 `btrfs subvolume list /`；
3. 显示前 20 个子卷；
4. 提供 30 秒倒计时菜单：

```text
1) Snapshot all snapper configs
2) Snapshot only the @ subvolume (root config)
3) Do not snapshot (abort deployment)
```

规则：

- 30 秒内没有有效选择：超时退出；
- 出现任何 snapper/btrfs 错误：退出；
- 选择 3：按设计中止部署；
- 非 Btrfs、未安装 snapper 或没有 snapper 配置：自动跳过；
- 快照创建发生在写 hosts 和改网络之前。

## 网络检测与静态 IP/DNS

### 检测顺序

1. **NetworkManager（优先）**
2. systemd-networkd
3. ifupdown
4. dhcpcd / ConnMan / iwd / netctl（只检测，静态配置不直接使用）

静态配置后端选择：

- NetworkManager：有 active 连接时使用 `nmcli`；
- systemd-networkd：服务 active 时写 `/etc/systemd/network/99-github520-<iface>.network`；
- ifupdown：`/etc/network/interfaces` 或 `interfaces.d` 中含目标接口时改写 stanza；
- 都不支持：报错退出。

### NetworkManager

```bash
nmcli connection modify <uuid> \
  ipv4.method manual \
  ipv4.addresses 192.168.1.50/24 \
  ipv4.gateway 192.168.1.1 \
  ipv4.dns 1.1.1.1,8.8.8.8 \
  ipv4.ignore-auto-dns yes
nmcli connection up <uuid>
```

修改前会保存旧字段，验证失败时尝试恢复。

### systemd-networkd

写入 99 优先级的 `.network` 文件，包含：

```ini
[Match]
Name=eth0

[Network]
DHCP=no
Address=192.168.1.50/24
Gateway=192.168.1.1
DNS=1.1.1.1
```

然后执行 `networkctl reload` 和 `networkctl reconfigure <iface>`。

### ifupdown

重写目标接口的 stanza。注意：**这可能丢失 MTU、bridge、bond、VLAN、pre-up 等额外选项**。复杂网络环境建议手动修改，或在快照中操作。

### DNS

按顺序尝试：

1. systemd-resolved：`resolvectl dns <iface> ...`；
2. `resolvconf`；
3. 直接写 `/etc/resolv.conf`（如果是符号链接则拒绝覆盖）。

修改静态 IP 或重启网络接口可能中断 SSH，请优先使用本地控制台或云控制台。

## systemd timer 与 service

安装后会复制脚本到：

```text
/usr/local/bin/github520-arch.sh
```

> 注意大小写：仓库文件是 `Github520-Arch.sh`，安装后的固定路径是小写 `github520-arch.sh`。

Service：

```text
/etc/systemd/system/github520-update.service
```

核心配置：

```ini
[Service]
Type=oneshot
ExecStart=/usr/local/bin/github520-arch.sh --update
```

Timer：

```text
/etc/systemd/system/github520-update.timer
```

核心配置：

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

- 安装完成后立即更新一次 hosts；
- 开机 5 分钟后第一次 timer 运行；
- 之后每小时运行一次；
- 每次运行调用 `--update`，非交互更新 hosts；
- 更新成功或失败写入日志；
- 更新模式不会创建快照、不会修改网络、不会重新安装 timer。

常用命令：

```bash
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
systemctl start github520-update.service
journalctl -u github520-update.service
tail -f /var/log/github520/update.log
```

手动执行一次更新：

```bash
sudo /usr/local/bin/github520-arch.sh --update
```

## 日志与备份

### 更新日志

```text
/var/log/github520/update.log
```

每次运行会写入：

- 开始时间；
- 使用的源；
- 下载/校验结果；
- hosts 是否变化；
- 成功或失败；
- 失败原因。

日志超过 1 MiB 时会轮转为 `update.log.1`。

### hosts 备份

```text
/var/backups/github520/hosts.<YYYYmmdd-HHMMSS>.<pid>
```

默认保留最近 24 份。只有 hosts 内容发生变化时才创建新备份。

手动恢复：

```bash
sudo cp /var/backups/github520/hosts.20260101-120000.1234 /etc/hosts
```

### 网络备份

```text
/var/backups/github520/net-<时间>.<pid>/
```

包含 NetworkManager 旧字段、networkd/ifupdown 配置文件、resolv.conf 备份（如果直接修改过）。

### 临时文件

安装/更新使用的 `mktemp` 目录会在退出时自动删除。

## 更新、卸载与还原

### 更新脚本

如果修改了仓库中的 `Github520-Arch.sh`，重新运行安装器即可覆盖 `/usr/local/bin/github520-arch.sh` 并重启 timer：

```bash
sudo ./Github520-Arch.sh
```

### 卸载 timer/service

```bash
sudo systemctl disable --now github520-update.timer
sudo rm -f /etc/systemd/system/github520-update.timer
sudo rm -f /etc/systemd/system/github520-update.service
sudo systemctl daemon-reload
sudo rm -f /usr/local/bin/github520-arch.sh
```

### 还原 hosts

```bash
sudo cp /var/backups/github520/hosts.<时间>.<pid> /etc/hosts
```

或者只删除 GitHub520 块：

```bash
sudo sed -i '/# GitHub520 Host Start/,/# GitHub520 Host End/d' /etc/hosts
```

日志和备份目录可按需删除：

```bash
sudo rm -rf /var/log/github520 /var/backups/github520
```

## 安全说明

- 脚本以 root 权限修改 `/etc/hosts`，可能修改网络配置并安装 systemd unit。
- hosts 内容来自 GitHub520 及第三方 CDN/镜像；脚本校验结构和条目数量，但**没有域名白名单**。镜像被劫持时可能写入恶意解析记录。高安全环境请只使用官方源或自行增加白名单。
- 脚本不会安装软件包，不会修改防火墙或 SSH 配置。
- timer 以 root 执行本地脚本；请确保 `/usr/local/bin/github520-arch.sh` 权限为 `0755` 且不可被普通用户篡改。
- Beta 版本请先在测试机或快照中验证。
- 本项目不是 GitHub520 官方项目。

## 常见问题 Q&A

### Q1: 为什么提示只支持 Arch Linux？

脚本会读取 `/etc/os-release` 的 `ID`，只有 `ID=arch` 才继续。Manjaro、EndeavourOS、Garuda 等 Arch 衍生版目前也会被拒绝。

### Q2: 在 Arch WSL 或容器里能运行吗？

理论上 `ID=arch` 会通过，但脚本需要 systemd 且在 `/run/systemd/system` 存在。大多数 WSL/容器默认不满足，会在 systemd 检查处退出。请勿在隔离环境中修改宿主机的网络配置。

### Q3: 没有 sudo 怎么办？

使用 root 登录，或让管理员把账号加入 sudoers。脚本没有 sudo 时会输出访问拒绝并退出。

### Q4: 快照菜单超时了？

这是设计行为：30 秒内没有有效选择会中止。重新运行并选择 1 或 2；不需要快照时选择 3 会主动中止安装。

### Q5: 所有 GitHub520 源都失败？

脚本会在写 hosts 前退出，不修改现有配置。请检查：

- 网络和 DNS；
- 是否能访问 `https://raw.hellogithub.com/hosts`；
- 代理/防火墙/TLS 拦截；
- 系统时间是否正确。

### Q6: hosts 写入失败或提示 immutable？

检查：

```bash
lsattr /etc/hosts
```

如果有 `i` 属性：

```bash
sudo chattr -i /etc/hosts
```

修改完成后可以按需加回。

### Q7: 为什么安装后 /etc/hosts 没变化？

可能已经是相同内容。脚本会检测 `cmp`，如果 hosts 已是最新，会显示 `Hosts already up to date`，不会重复备份或写入。

### Q8: timer 没有运行？

检查：

```bash
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
systemctl status github520-update.service
journalctl -u github520-update.service
```

常见原因：

- systemd 不是 PID 1；
- timer 被手动 disable；
- 脚本路径 `/usr/local/bin/github520-arch.sh` 被删除；
- unit 文件被修改但未 `daemon-reload`。

### Q9: 如何立即测试自动更新？

```bash
sudo systemctl start github520-update.service
tail -n 50 /var/log/github520/update.log
```

### Q10: 自动更新会改网络吗？

不会。`--update` 只更新 hosts 和刷新 DNS 缓存，不创建快照、不修改静态 IP/DNS，也不会重装 timer。

### Q11: 静态 IP 修改后 SSH 断开了？

脚本会二次确认，但无法保证远程连接不中断。请使用本地/云控制台登录，然后：

1. 查看 `/var/backups/github520/net-*`；
2. 恢复旧配置；
3. 重启 NetworkManager、systemd-networkd 或 ifupdown；
4. 或恢复快照。

### Q12: 为什么优先使用 NetworkManager？

Arch 桌面和很多服务器使用 NetworkManager。脚本会优先检查 `nmcli` 和 active 连接；没有可用 NM 连接时才回退到 systemd-networkd/ifupdown。

### Q13: DNS 修改没生效？

检查：

```bash
resolvectl dns
cat /etc/resolv.conf
```

可能原因：

- systemd-resolved 未启用；
- `/etc/resolv.conf` 是符号链接，脚本拒绝覆盖；
- 其他网络配置优先级更高；
- 修改后未重新激活连接。

### Q14: ifupdown 的 bridge/bond/VLAN 会保留吗？

`--static-ip` 对应的 ifupdown 逻辑会重写目标 stanza，可能丢失 MTU、bridge、bond、VLAN、pre-up 等选项。复杂网络请手动修改，或先做快照/备份。

### Q15: 如何卸载？

```bash
sudo systemctl disable --now github520-update.timer
sudo rm -f /etc/systemd/system/github520-update.timer
sudo rm -f /etc/systemd/system/github520-update.service
sudo systemctl daemon-reload
sudo rm -f /usr/local/bin/github520-arch.sh
```

然后用备份还原 `/etc/hosts`。

### Q16: 这是正式版吗？

不是。当前是 **v0.1 beta**。欢迎反馈问题，但请勿在未备份的生产环境直接使用。

---

# English

GitHub520 hosts installer for **Arch Linux** (Beta).

- Version: **v0.1 (beta)**
- Author: **白丝小猫娘 (WS-CatGirl)**
- New script: [Github520-Arch.sh](Github520-Arch.sh)
- Legacy generic script: [github520-deploy.sh](github520-deploy.sh)

> This is not an official GitHub520 project. Hosts content comes from GitHub520 and its mirrors.
>
> Beta software. Keep backups and test on a non-critical machine first.

## Features

- Catgirl-style welcome screen with version **v0.1 beta**.
- **Arch Linux only** (`ID=arch` in `/etc/os-release`). Manjaro, EndeavourOS and other Arch derivatives are rejected.
- Root/sudo handling:
  - root runs directly;
  - a normal user with sudo is re-executed through sudo;
  - missing sudo or failed authentication produces an access-denied message.
- Optional Btrfs/snapper snapshot with a 30-second countdown.
- Detects **NetworkManager first**, then systemd-networkd, ifupdown, dhcpcd, ConnMan, iwd and netctl.
- Multiple GitHub520 sources with automatic fallback.
- Backs up `/etc/hosts` before writing and restores it on failure.
- Optional static IPv4, gateway and DNS configuration.
- Installs a systemd service + hourly timer for automatic updates.
- Writes success/failure details to `/var/log/github520/update.log`.
- Bilingual/catgirl-style welcome and final summary; runtime messages remain readable in a TTY.

## Requirements

- Arch Linux (`ID=arch`)
- systemd
- bash 4+
- `curl`, `ip` (iproute2), `findmnt`, `awk`, `sed`, `grep`, `mktemp`, `install`
- Optional: Btrfs + snapper + btrfs-progs
- Optional: NetworkManager (recommended), systemd-networkd, ifupdown
- Optional: systemd-resolved, resolvconf, nscd or dnsmasq for DNS handling

## Quick start

```bash
git clone https://github.com/WS-CatGirl/github520-deploy.git
cd github520-deploy

chmod +x Github520-Arch.sh
sudo ./Github520-Arch.sh
```

Help and version:

```bash
./Github520-Arch.sh --help
./Github520-Arch.sh --version
```

## Options

| Option | Description |
|---|---|
| `-h`, `--help` | Show help and exit. No root required. |
| `-V`, `--version` | Show version and exit. |
| `--update` | Internal non-interactive mode used by the systemd timer. Updates hosts, writes the log and exits. |

## Install flow

1. Welcome.
2. Root/sudo check.
3. Arch Linux check.
4. Optional Btrfs/snapper snapshot.
5. Network backend detection (NetworkManager first).
6. GitHub520 source check and download.
7. Backup and update `/etc/hosts`.
8. Optional static IPv4/DNS configuration.
9. Install and enable `github520-update.timer`.
10. Cleanup and final summary.

## Snapshots

On Btrfs with snapper:

```text
1) Snapshot all snapper configs
2) Snapshot only the @ subvolume (root config)
3) Do not snapshot (abort deployment)
```

A timeout, snapper error or option 3 aborts the deployment. Non-Btrfs systems and systems without snapper configs skip this step.

## Network configuration

Priority:

1. NetworkManager
2. systemd-networkd
3. ifupdown

Static configuration:

- NetworkManager: `nmcli connection modify ...` + `connection up`;
- systemd-networkd: writes `/etc/systemd/network/99-github520-<iface>.network` and reloads;
- ifupdown: rewrites the target stanza. Complex options such as MTU/bridge/bond/VLAN may be lost.

DNS is applied through systemd-resolved, resolvconf, or a direct `/etc/resolv.conf` write (symlinks are not overwritten).

Changing the IP or restarting an interface may interrupt SSH. Use a local/out-of-band console.

## systemd timer and service

Installed script:

```text
/usr/local/bin/github520-arch.sh
```

Unit files:

```text
/etc/systemd/system/github520-update.service
/etc/systemd/system/github520-update.timer
```

Timer schedule:

```ini
OnBootSec=5min
OnUnitActiveSec=1h
AccuracySec=1min
RandomizedDelaySec=30s
Persistent=true
```

Useful commands:

```bash
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
systemctl start github520-update.service
journalctl -u github520-update.service
tail -f /var/log/github520/update.log
```

## Logs and backups

- Update log: `/var/log/github520/update.log` (rotated at 1 MiB).
- Hosts backups: `/var/backups/github520/hosts.<timestamp>.<pid>` (latest 24).
- Network backups: `/var/backups/github520/net-<timestamp>.<pid>/`.

Restore hosts:

```bash
sudo cp /var/backups/github520/hosts.<timestamp>.<pid> /etc/hosts
```

## Uninstall

```bash
sudo systemctl disable --now github520-update.timer
sudo rm -f /etc/systemd/system/github520-update.timer
sudo rm -f /etc/systemd/system/github520-update.service
sudo systemctl daemon-reload
sudo rm -f /usr/local/bin/github520-arch.sh
```

Restore `/etc/hosts` from the backup if needed.

## Security notes

- The installer runs as root and modifies system files, network settings and systemd units.
- Hosts content comes from third-party CDNs/mirrors. The script validates structure and entry count but does not enforce a domain allowlist. Use the official source or add your own allowlist for high-security environments.
- The timer executes a local root-owned script. Ensure `/usr/local/bin/github520-arch.sh` remains root-owned and not writable by unprivileged users.
- No packages, firewall rules or SSH configuration are modified.
- This is a beta release.

## FAQ

### 1. Why is only Arch Linux supported?

The script checks `ID=arch` in `/etc/os-release`. Arch derivatives currently fail this check.

### 2. Does it work in Arch WSL/containers?

The systemd check (`/run/systemd/system`) usually fails in WSL/containers. Do not modify host networking from an isolated environment.

### 3. The snapshot menu timed out

A valid selection is required within 30 seconds. Re-run and choose 1 or 2, or choose 3 to abort.

### 4. All sources failed

The script exits before modifying hosts. Check network, DNS, proxy, firewall, TLS interception and system time.

### 5. `/etc/hosts` is immutable

Check `lsattr /etc/hosts`; if the `i` attribute is set, run `sudo chattr -i /etc/hosts`.

### 6. Hosts did not change

The content may already be identical. The script skips backup/write and logs `Hosts already up to date`.

### 7. The timer is not running

Check:

```bash
systemctl status github520-update.timer
systemctl list-timers github520-update.timer
journalctl -u github520-update.service
```

Also verify `/usr/local/bin/github520-arch.sh` exists and the unit files have not been edited without `daemon-reload`.

### 8. Does the hourly update change networking?

No. `--update` only updates hosts and flushes DNS caches. It does not create snapshots, change IP/DNS, or reinstall the timer.

### 9. SSH disconnected after a static IP change

Use a local/cloud console, restore files from `/var/backups/github520/net-*`, restart the network backend, or restore a snapshot.

### 10. Why NetworkManager first?

It is the most common network stack on Arch desktops/servers. The script uses an active `nmcli` connection first, then falls back to systemd-networkd/ifupdown.

### 11. DNS did not change

Check `resolvectl dns` and `/etc/resolv.conf`. `/etc/resolv.conf` symlinks are not overwritten; another backend may have higher priority.

### 12. Will ifupdown bridge/bond/VLAN settings survive?

Static ifupdown configuration rewrites the stanza and may drop extra options. Use manual configuration or a snapshot for complex networking.

### 13. How do I uninstall?

Disable/remove the timer and service, remove `/usr/local/bin/github520-arch.sh`, then restore `/etc/hosts` from backup.

### 14. Is this stable?

No. This is **v0.1 beta**. Keep backups and report issues.
