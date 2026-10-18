# GitHub520 Deploy for Linux

一个用于在原生 Linux 上部署 [GitHub520](https://github.com/521xueweihan/GitHub520) hosts 规则的交互式脚本。它会自动选择可用的 GitHub520 源、备份并更新 `/etc/hosts`，并可选地配置静态 IPv4 和 DNS。

> 本项目不是 GitHub520 官方项目。hosts 内容来自 GitHub520 及其镜像源，脚本只负责下载、校验和写入。
>
> 当前默认行为是 **只更新 `/etc/hosts`**，不会自动修改网络配置。静态 IP 和 DNS 修改必须显式使用 `--static-ip` 或 `--dns-only`。

---

## 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [默认行为](#默认行为)
- [命令行参数](#命令行参数)
- [使用示例](#使用示例)
- [执行流程](#执行流程)
- [Btrfs 与 snapper 快照](#btrfs-与-snapper-快照)
- [静态 IP 与 DNS 模式](#静态-ip-与-dns-模式)
- [回滚与备份](#回滚与备份)
- [GitHub520 源与回退](#github520-源与回退)
- [安全说明](#安全说明)
- [常见问题 Q&A](#常见问题-qa)
- [English](#english)

---

## 功能特性

- 仅支持 Linux；拒绝 Windows、macOS、WSL、Docker/Podman/LXC 等容器环境。
- 检测到 KVM/QEMU/VMware/Hyper-V/Xen 等虚拟机时先警告，交互确认后继续；可用 `--allow-vm` 或 `--yes` 跳过询问。
- 自动处理 root/sudo：
  - root 直接运行；
  - 普通用户有可用 sudo 时自动提权；
  - 没有 sudo 或认证失败时给出明确提示并退出。
- Btrfs + snapper 环境下支持创建快照，带 30 秒倒计时菜单；可用 `--no-snapshot` 跳过。
- 内置多个 GitHub520 源，单个源请求失败、HTTP 非 200、内容为空或格式无效时自动切换到下一个源。
- 写入 `/etc/hosts` 前自动备份；写入失败或校验失败时自动恢复。
- 可选静态 IPv4、网关和 DNS 配置，支持 NetworkManager、netplan、systemd-networkd、ifupdown。
- 网络修改会进行结果验证，验证失败时尝试自动回滚，并保留备份。
- 支持 `--dry-run` 预览，不写 hosts、不建快照、不改网络、不刷 DNS 缓存。
- 所有终端输出均为英文，便于在无法显示中文的 TTY 中使用。

## 系统要求

- Linux（原生环境；WSL/容器会被拒绝）
- bash 4 或更新版本
- 常用命令：
  - `curl`
  - `ip`（iproute2）
  - `findmnt`（util-linux，通常已安装）
  - `awk`、`sed`、`grep`、`mktemp` 等 coreutils/findutils 工具
- 可选：
  - Btrfs 根文件系统 + `snapper` + `btrfs-progs`
  - NetworkManager、netplan、systemd-networkd 或 ifupdown 之一
  - `systemd-resolved`、`resolvconf` 或 `nscd`/`dnsmasq`（用于 DNS 生效和缓存刷新）

脚本会使用 `#!/usr/bin/env bash`，请不要用 `sh` 执行。即使使用 `sh github520-deploy.sh` 启动，脚本也会自动转用 bash；但系统必须已安装 bash 4+。

## 快速开始

```bash
git clone https://github.com/WS-CatGirl/github520-deploy.git
cd github520-deploy

chmod +x github520-deploy.sh
sudo ./github520-deploy.sh
```

普通用户也可以直接执行，脚本会请求 sudo：

```bash
./github520-deploy.sh
```

查看帮助：

```bash
./github520-deploy.sh --help
```

只预览，不做任何修改（不需要 root）：

```bash
./github520-deploy.sh --dry-run
```

## 默认行为

不带任何参数时，脚本只做以下事情：

1. 检查权限、系统和网络；
2. 在 Btrfs + snapper 环境询问是否创建快照；
3. 检测并下载 GitHub520 hosts；
4. 备份 `/etc/hosts`；
5. 删除旧的 GitHub520 块并写入新块；
6. 刷新 DNS 缓存；
7. 输出摘要。

**不会询问或修改静态 IP / DNS。** 要修改网络，必须显式使用：

- `--static-ip`：修改静态 IPv4、网关和可选 DNS；
- `--dns-only`：只修改 DNS，保留当前 IP 和网关。

## 命令行参数

| 参数 | 说明 |
|---|---|
| `-h`, `--help` | 显示帮助并退出，不需要 root。 |
| `-y`, `--yes` | 自动确认虚拟机警告和网络修改确认；不会自动填写 IP/DNS，也不会自动选择快照菜单。 |
| `--dry-run` | 预览模式：下载和校验源，但不写 hosts、不建快照、不改网络、不刷 DNS。不需要 root。 |
| `--no-snapshot` | 跳过 Btrfs/snapper 快照步骤。 |
| `--hosts-only` | 只更新 hosts，等同于默认行为。 |
| `--dns-only` | 更新 hosts 后只修改 DNS，保留当前 IP 和网关。 |
| `--static-ip` | 更新 hosts 后配置静态 IPv4、网关和可选 DNS。 |
| `--source <url>` | 使用指定的 GitHub520 源，可重复。指定后替代内置源列表。 |
| `--allow-vm` | 检测到虚拟机时直接继续，不再询问。Docker/WSL/容器仍然拒绝。 |
| `--` | 选项结束标记。 |

`--hosts-only`、`--dns-only`、`--static-ip` 三者互斥，同时使用会报错。

### 参数组合建议

| 场景 | 命令 |
|---|---|
| 只更新 hosts（默认） | `sudo ./github520-deploy.sh` |
| 跳过快照，自动确认虚拟机 | `sudo ./github520-deploy.sh --no-snapshot --yes` |
| 只改 DNS | `sudo ./github520-deploy.sh --dns-only` |
| 改静态 IP | `sudo ./github520-deploy.sh --static-ip` |
| 预览静态 IP 流程 | `./github520-deploy.sh --dry-run --static-ip` |
| 指定源 | `sudo ./github520-deploy.sh --source https://raw.hellogithub.com/hosts` |

## 使用示例

### 1. 普通部署

```bash
sudo ./github520-deploy.sh
```

脚本会在需要时请求 sudo 密码，然后按上述默认流程更新 hosts。

### 2. 非交互式更新 hosts

```bash
sudo ./github520-deploy.sh --hosts-only --no-snapshot --yes
```

适用于 cron、配置管理或自动化脚本。`--yes` 只确认警告和确认框；如果系统是 Btrfs + snapper 且没有 `--no-snapshot`，仍然会出现快照菜单。

### 3. 只改 DNS

```bash
sudo ./github520-deploy.sh --dns-only
```

脚本会提示 DNS1、DNS2，然后根据当前网络后端修改 DNS，保留 IP 地址和网关。

### 4. 配置静态 IPv4

```bash
sudo ./github520-deploy.sh --static-ip
```

脚本会显示当前接口、地址和网关，并提示输入：

- 静态 IPv4（CIDR，例如 `192.168.1.50/24`）
- DNS1
- DNS2（可留空）

修改前会再次确认。修改后会检查地址是否生效，失败时尝试回滚。

### 5. Dry run

```bash
./github520-deploy.sh --dry-run --static-ip
```

会执行系统/网络/源检测，并显示计划修改的 hosts diff，但不会进行任何持久化修改。由于没有输入实际 IP/DNS，dry-run 不会真正执行网络配置。

### 6. 使用自定义源

```bash
sudo ./github520-deploy.sh --source https://raw.hellogithub.com/hosts
```

也可以重复指定多个源：

```bash
sudo ./github520-deploy.sh \
  --source https://raw.hellogithub.com/hosts \
  --source https://fastly.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts
```

指定 `--source` 后，内置源列表会被替换，不再自动使用其他内置镜像。

## 执行流程

1. **参数解析**：先处理 `--help`，因此非 root 也可以查看帮助。
2. **权限检查**：根据是否 root、是否可用 sudo 决定直接运行或重新提权。
3. **系统检查**：
   - 拒绝非 Linux、WSL、容器；
   - 检测虚拟机并警告，交互确认或使用 `--allow-vm` / `--yes`；
   - 读取 `/etc/os-release` 显示发行版。
4. **文件系统检查**：
   - 非 Btrfs 跳过；
   - Btrfs 且 snapper 有配置时，列出 snapper 配置和 Btrfs 子卷；
   - 30 秒倒计时选择快照范围；超时、错误或选择“不创建”都会中止。
5. **网络与源检测**：
   - 探测 NetworkManager、ifupdown、netplan、systemd-networkd 等；
   - 读取默认路由、接口、网关和当前 IPv4；
   - 逐个探测 GitHub520 源。
6. **下载与校验**：
   - 逐源下载；
   - 校验 HTTP 200、非空、`# GitHub520 Host Start/End` 唯一、至少 5 条 IP/域名映射；
   - 全部失败则在修改 hosts 前退出。
7. **更新 hosts**：
   - 备份 `/etc/hosts`；
   - 用 awk 删除旧 GitHub520 块；
   - 追加新块并验证；
   - 写入失败或验证失败时用备份恢复；
   - 刷新 DNS 缓存。
8. **可选网络配置**：
   - 默认跳过；
   - `--static-ip` 或 `--dns-only` 时选择后端、收集参数、确认、应用、验证；
   - 验证失败时回滚。
9. **输出摘要**：hosts 源、条目数、快照、网络模式、备份位置。

## Btrfs 与 snapper 快照

当根文件系统是 Btrfs，且安装了 snapper 并存在配置时，脚本会：

1. 执行 `snapper list-configs`；
2. 执行 `btrfs subvolume list /`；
3. 显示前 20 个子卷；
4. 提供三个选择：

```text
1) Snapshot all snapper configs (all subvolumes)
2) Snapshot only the @ subvolume (root config)
3) Do not snapshot (abort deployment)
```

- 30 秒内没有有效选择会超时退出；
- 选择 3 会按设计中止部署；
- 任一 snapper 命令失败会退出；
- 使用 `--no-snapshot` 可完全跳过该步骤。

注意：`--yes` **不会**自动替你选择快照范围。自动化场景请显式加 `--no-snapshot`，或保留交互终端。

## 静态 IP 与 DNS 模式

### 后端选择顺序

脚本按以下顺序选择：

1. NetworkManager（`nmcli` 且服务处于 active）
2. netplan（存在 `/etc/netplan/*.yaml`）
3. systemd-networkd（服务 active）
4. ifupdown（`/etc/network/interfaces` 或 `interfaces.d` 中含目标接口）

如果检测到多个后端，会优先使用排在前面的。若目标接口没有对应的活动连接，可能回退到其他后端；修改前建议先确认当前实际由谁管理网络。

### `--static-ip`

- 使用当前默认路由的接口和网关；
- 输入 IPv4 CIDR；
- DNS1、DNS2 可沿用当前值；
- 修改前会二次确认；
- 修改后会验证新地址是否出现在接口上；
- 验证失败会调用回滚，并保留 `/var/backups/github520-*` 备份。

### `--dns-only`

- 保留当前 IP 和网关；
- 只修改 DNS；
- NetworkManager：设置 `ipv4.dns` 并重新激活连接；
- netplan：写入只包含 `nameservers` 的 90 优先级文件；
- systemd-networkd：写入只包含 `DNS=` 和 `[DHCP] UseDNS=no` 的文件；
- ifupdown：只替换目标 stanza 中的 `dns-nameservers`，保留其他选项；
- 修改后验证 DNS 是否出现在 `resolvectl` 或 `/etc/resolv.conf` 中。

### 远程连接风险

修改静态 IP 或重启网络接口可能中断 SSH。脚本会警告并二次确认，但无法保证远程会话不中断。建议：

- 在本地控制台或带外管理（IPMI、云控制台）下操作；
- 先确认新 IP、网关、子网和 DNS 正确；
- 保留当前会话，直到验证新地址可访问；
- 如果失联，使用云控制台恢复，或从 `/var/backups/github520-*` 还原配置。

## 回滚与备份

### hosts 备份

每次写入前创建：

```text
/etc/hosts.github520-backup.<YYYYmmdd-HHMMSS>.<pid>
```

写入或校验失败时，退出钩子会自动恢复该备份。

手动恢复：

```bash
sudo cp /etc/hosts.github520-backup.20260101-120000.1234 /etc/hosts
```

### 网络配置备份

网络修改前创建：

```text
/var/backups/github520-<YYYYmmdd-HHMMSS>.<pid>/
```

其中包含：

- NetworkManager 连接的旧字段快照；
- 被覆盖的 netplan 文件；
- 被覆盖的 systemd-networkd 文件；
- 被覆盖的 ifupdown 文件；
- `/etc/resolv.conf` 备份（如果脚本直接修改过它）。

网络验证失败、收到 INT/TERM/HUP 或应用过程中出错时，脚本会尝试自动回滚。若自动回滚不完整，请根据备份目录手动恢复，然后重启对应网络服务。

### 注意

自动回滚无法覆盖断电、内核崩溃、强制 kill -9 或网络服务自身异常等情况。重要机器请先做快照或手动备份。

## GitHub520 源与回退

内置源：

1. `https://raw.hellogithub.com/hosts`（官方）
2. `https://fastly.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
3. `https://gcore.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
4. `https://testingcf.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
5. `https://quantil.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
6. `https://cdn.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
7. `https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts`

下载逻辑：

- 每个源最多尝试两次；
- 请求失败、HTTP 非 200、空文件、格式校验失败都会跳到下一个；
- 所有源失败时立即退出，不备份、不修改 `/etc/hosts`；
- `--source` 可替换为自定义源列表。

## 安全说明

- 脚本以 root 权限修改 `/etc/hosts`，并可能修改网络配置。运行前请阅读代码。
- hosts 内容来自第三方 CDN/镜像。脚本目前校验结构、标记和条目数量，但**没有**对域名做严格白名单校验。若镜像被劫持，可能写入恶意解析记录。对安全要求高的环境，建议只使用官方源，或自行增加域名白名单。
- 脚本不会安装软件包，不会修改防火墙，不会修改 SSH 配置。
- `--dry-run` 不会写 hosts 或网络配置，但仍会发起 HTTPS 请求。
- 脚本不保存任何凭据；sudo 认证由系统 sudo 处理。

## 常见问题 Q&A

### Q1: 提示 “Virtual machine detected”，还能继续吗？

可以。脚本会先警告，然后询问是否继续。选择 `y` 即可。也可以使用：

```bash
sudo ./github520-deploy.sh --allow-vm
# 或
sudo ./github520-deploy.sh --yes
```

Docker、Podman、LXC、WSL 等容器环境仍然会被直接拒绝，`--allow-vm` 不会绕过。

### Q2: 为什么 WSL 和 Docker 不能运行？

脚本会直接修改宿主机/系统的 `/etc/hosts` 和网络配置，而 WSL/容器中的 `/etc/hosts` 通常是隔离的，修改不会按预期作用到宿主机；网络后端也可能不可用。因此设计上直接拒绝。

### Q3: Btrfs 快照菜单超时了怎么办？

这是设计行为：30 秒内没有有效选择会中止。重新运行并尽快选择，或使用：

```bash
sudo ./github520-deploy.sh --no-snapshot
```

### Q4: 所有 GitHub520 源都失败怎么办？

脚本会在修改 hosts 前退出。请检查：

- 是否能访问 `https://raw.hellogithub.com/hosts`；
- DNS 是否正常；
- 是否需要 HTTP(S) 代理；
- 防火墙/安全组是否拦截 443；
- 是否在公司网络中被 TLS 拦截。

可以指定一个可用源：

```bash
sudo ./github520-deploy.sh --source https://raw.hellogithub.com/hosts
```

### Q5: 提示 `/etc/hosts` 不可写或 immutable 怎么办？

检查属性：

```bash
lsattr /etc/hosts
```

如果带有 `i` 属性：

```bash
sudo chattr -i /etc/hosts
```

修改完成后再根据需要加回。也请确认文件系统不是只读挂载。

### Q6: hosts 已更新，但 GitHub 仍然很慢或图片打不开？

可能原因：

- DNS 缓存未刷新：重启网络或执行 `resolvectl flush-caches`；
- 浏览器/系统使用了 DoH 或代理，绕过 hosts；
- GitHub520 当前 IP 对您的网络不是最优；
- 目标域名没有被 hosts 覆盖；
- 公司网络/防火墙限制。

可用以下命令确认解析：

```bash
getent hosts github.com
```

### Q7: 静态 IP 修改后 SSH 断开了怎么办？

脚本会警告并二次确认，但网络修改本身可能导致连接中断。请使用云控制台/本地控制台登录，然后：

1. 查看 `/var/backups/github520-*`；
2. 恢复旧配置文件；
3. 重启 NetworkManager/netplan/systemd-networkd/ifupdown；
4. 或直接恢复机器快照。

### Q8: `--dns-only` 后 DNS 没生效？

检查：

```bash
resolvectl dns
cat /etc/resolv.conf
```

可能的原因：

- 后端不是 systemd-resolved，而是 dnsmasq/NetworkManager；
- `/etc/resolv.conf` 是符号链接，脚本拒绝直接覆盖；
- 另一个网络配置文件的 DNS 优先级更高；
- DNS 修改后没有重新激活连接。

可以查看脚本输出的 `network backend` 和备份目录，确认实际后端。

### Q9: ifupdown 配置很复杂（bridge/bond/VLAN）会怎样？

`--static-ip` 会重写目标接口的 stanza，可能丢失 MTU、bridge、bond、VLAN、pre-up 等选项。复杂网络环境建议：

- 不要使用 `--static-ip`；
- 手动修改 `/etc/network/interfaces`；
- 或先测试 `--dry-run` / 在快照中操作。

`--dns-only` 只替换 `dns-nameservers`，对其他选项更安全。

### Q10: 为什么默认不改网络了？

为了避免脚本在无人值守或远程环境下意外改坏网络。默认只更新 hosts；需要网络修改时显式加 `--static-ip` 或 `--dns-only`。

### Q11: `--yes` 会自动选择快照吗？

不会。`--yes` 只自动确认虚拟机警告和网络修改确认。快照范围涉及数据安全，仍需要交互选择；自动化请用 `--no-snapshot`。

### Q12: `--dry-run` 为什么没有提示输入 IP/DNS？

dry-run 只做检测、下载、校验和差异预览，不执行网络配置，因此不会收集实际 IP/DNS，也不会修改网络。它仍会显示将要使用的网络模式和后端。

### Q13: 如何完全卸载/恢复？

推荐从备份恢复：

```bash
sudo cp /etc/hosts.github520-backup.<时间>.<pid> /etc/hosts
```

或删除 hosts 中的 GitHub520 块：

```bash
sudo sed -i '/# GitHub520 Host Start/,/# GitHub520 Host End/d' /etc/hosts
```

网络配置请根据 `/var/backups/github520-*` 手动恢复。

### Q14: 为什么脚本输出全是英文？

因为很多 TTY/救援环境无法正确显示中文。README 提供中文说明，脚本本身的运行日志保持英文。

---

# English

A bash script that deploys [GitHub520](https://github.com/521xueweihan/GitHub520) hosts entries on native Linux. It selects a working GitHub520 source, backs up and updates `/etc/hosts`, and can optionally configure a static IPv4 address and DNS servers.

> This is not an official GitHub520 project. The hosts content comes from GitHub520 and its mirrors; this script only downloads, validates and writes it.
>
> The default action is **hosts-only**. Network changes require `--static-ip` or `--dns-only`.

## Features

- Native Linux only. Windows, macOS, WSL, Docker/Podman/LXC and other containers are rejected.
- Virtual machines (KVM/QEMU/VMware/Hyper-V/Xen, etc.) trigger a warning and confirmation. Use `--allow-vm` or `--yes` to continue without the prompt.
- Automatic privilege handling:
  - root runs directly;
  - a normal user with sudo is re-executed through sudo;
  - missing sudo or failed authentication produces a clear access-denied message.
- Optional Btrfs/snapper snapshot with a 30-second countdown. Use `--no-snapshot` to skip it.
- Multiple built-in GitHub520 sources with automatic fallback on request failure, non-200 HTTP status, empty content or invalid format.
- Backs up `/etc/hosts` before writing and restores it if writing or verification fails.
- Optional static IPv4, gateway and DNS configuration for NetworkManager, netplan, systemd-networkd and ifupdown.
- Network changes are verified; failed verification triggers a rollback attempt. Backups are retained.
- `--dry-run` previews without writing hosts, creating snapshots, changing network settings or flushing DNS.
- All runtime output is English, suitable for TTYs that cannot display Chinese.

## Requirements

- Linux (native; WSL/containers rejected, VMs require confirmation)
- bash 4+
- `curl`, `ip` (iproute2), `findmnt` (util-linux), `awk`, `sed`, `grep`, `mktemp`
- Optional: Btrfs + snapper + btrfs-progs
- Optional: NetworkManager, netplan, systemd-networkd or ifupdown
- Optional: systemd-resolved, resolvconf, nscd or dnsmasq for DNS handling/cache flushing

## Quick start

```bash
git clone https://github.com/WS-CatGirl/github520-deploy.git
cd github520-deploy

chmod +x github520-deploy.sh
sudo ./github520-deploy.sh
```

A normal user can also run it directly; the script will request sudo:

```bash
./github520-deploy.sh
```

Show help:

```bash
./github520-deploy.sh --help
```

Preview without changing anything (no root required):

```bash
./github520-deploy.sh --dry-run
```

## Default behavior

With no options, the script:

1. checks privileges, OS and network;
2. asks about a snapshot on Btrfs + snapper;
3. detects and downloads GitHub520 hosts;
4. backs up `/etc/hosts`;
5. removes the old GitHub520 block and appends the new one;
6. flushes DNS caches;
7. prints a summary.

It does **not** ask about or modify static IP/DNS by default. Use:

- `--static-ip` to configure a static IPv4 address, gateway and optional DNS;
- `--dns-only` to change DNS only, keeping the current IP and gateway.

## Options

| Option | Description |
|---|---|
| `-h`, `--help` | Show help and exit. Does not require root. |
| `-y`, `--yes` | Auto-confirm the VM warning and network-change confirmation. Does not fill in IP/DNS or choose a snapshot range. |
| `--dry-run` | Download and validate, but do not create snapshots, write hosts, change network settings or flush DNS. No root required. |
| `--no-snapshot` | Skip the Btrfs/snapper snapshot step. |
| `--hosts-only` | Update hosts only. This is the default. |
| `--dns-only` | Update hosts, then change DNS only. Keep the current IP and gateway. |
| `--static-ip` | Update hosts, then configure static IPv4, gateway and optional DNS. |
| `--source <url>` | Use a specific GitHub520 source. May be repeated; replaces the built-in list. |
| `--allow-vm` | Continue on a detected virtual machine without asking. Docker/WSL/containers are still rejected. |
| `--` | End of options. |

`--hosts-only`, `--dns-only` and `--static-ip` are mutually exclusive.

## Examples

```bash
# Default: hosts only
sudo ./github520-deploy.sh

# Non-interactive hosts update
sudo ./github520-deploy.sh --hosts-only --no-snapshot --yes

# DNS only
sudo ./github520-deploy.sh --dns-only

# Static IPv4
sudo ./github520-deploy.sh --static-ip

# Preview
./github520-deploy.sh --dry-run --static-ip

# Custom source
sudo ./github520-deploy.sh --source https://raw.hellogithub.com/hosts
```

## Execution flow

1. Parse options. `--help` works without root.
2. Check privileges and re-execute through sudo if needed.
3. Reject non-Linux, WSL and containers. Warn and ask on virtual machines.
4. On Btrfs + snapper, list configs/subvolumes and ask for a snapshot range with a 30-second countdown.
5. Detect network backends and the default route.
6. Probe GitHub520 sources and download the first valid block, falling back on failures.
7. Back up `/etc/hosts`, remove the old block, append the new block, verify, and flush DNS caches.
8. If `--static-ip` or `--dns-only` is given, collect network values, confirm, apply, verify, and roll back on failure.
9. Print a summary.

## Snapshots

On Btrfs with snapper, the menu offers:

```text
1) Snapshot all snapper configs (all subvolumes)
2) Snapshot only the @ subvolume (root config)
3) Do not snapshot (abort deployment)
```

A timeout, snapper error or option 3 aborts the deployment. `--no-snapshot` skips the step. `--yes` does not choose a snapshot range automatically.

## Network modes

Backend priority: NetworkManager → netplan → systemd-networkd → ifupdown.

- `--static-ip`: uses the current interface and gateway, asks for an IPv4 CIDR, DNS1 and optional DNS2, confirms, applies, verifies and rolls back on failure.
- `--dns-only`: keeps the current IP/gateway and changes DNS only. It updates the selected backend and verifies the resolver configuration.

Changing the IP or restarting an interface can interrupt SSH. Use a local/out-of-band console when possible. Backups are stored under `/var/backups/github520-*`.

## Rollback and backups

- `/etc/hosts.github520-backup.<timestamp>.<pid>` — hosts backup.
- `/var/backups/github520-<timestamp>.<pid>/` — network configuration backups, including NetworkManager state, netplan/networkd/ifupdown files and `/etc/resolv.conf` if it was modified.

On hosts write/verification failure, the exit trap restores the hosts backup. On network verification failure or fatal signal, the script attempts a rollback. Automatic rollback cannot survive power loss, kernel panic or `kill -9`; use the backups or a VM/disk snapshot if needed.

## Sources

Built-in sources:

1. `https://raw.hellogithub.com/hosts` (official)
2. `https://fastly.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
3. `https://gcore.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
4. `https://testingcf.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
5. `https://quantil.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
6. `https://cdn.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts`
7. `https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts`

Each source is tried up to twice. Failures, non-200 status, empty files or invalid content trigger the next source. If every source fails, the script exits before touching `/etc/hosts`. `--source` replaces the built-in list.

## Security notes

- The script runs as root and modifies `/etc/hosts`; it may also change network configuration. Review it before use.
- Hosts content comes from third-party CDNs/mirrors. The script validates structure, markers and entry count, but does **not** enforce a strict domain allowlist. A compromised mirror could inject arbitrary DNS entries. For high-security environments, use only the official source or add your own allowlist.
- The script does not install packages, modify firewalls or change SSH configuration.
- `--dry-run` makes no persistent changes, but still performs HTTPS requests.
- No credentials are stored by the script; sudo authentication is handled by sudo.

## FAQ

### 1. “Virtual machine detected” — can I continue?

Yes. Confirm with `y`, or use `--allow-vm` / `--yes`. Docker, Podman, LXC, WSL and other containers are still rejected.

### 2. Why are WSL and Docker rejected?

`/etc/hosts` and network settings inside WSL/containers are typically isolated from the host, so changes may not affect the intended system. Network backends may also be unavailable.

### 3. The snapshot menu timed out

That is intentional: no valid selection within 30 seconds aborts. Re-run and choose, or use `--no-snapshot`.

### 4. All GitHub520 sources failed

The script exits before modifying hosts. Check connectivity to `https://raw.hellogithub.com/hosts`, DNS, proxy settings, firewall/security groups and TLS interception. You can specify a known-good source with `--source`.

### 5. `/etc/hosts` is immutable or not writable

Check `lsattr /etc/hosts`. If the immutable bit is set, run `sudo chattr -i /etc/hosts`, update, then restore the attribute if needed. Also check that the filesystem is not mounted read-only.

### 6. Hosts updated but GitHub is still slow

DNS caching, DoH/proxy bypass, non-optimal GitHub520 IPs, uncovered domains or firewall restrictions are common causes. Check with `getent hosts github.com`.

### 7. SSH disconnected after a static IP change

Use a cloud/local console, inspect `/var/backups/github520-*`, restore the old configuration and restart the network backend, or restore a VM/disk snapshot.

### 8. `--dns-only` did not take effect

Check `resolvectl dns` and `/etc/resolv.conf`. The active backend may be dnsmasq/NetworkManager, `/etc/resolv.conf` may be a symlink, another config may have higher priority, or the connection may not have been reactivated.

### 9. Will ifupdown bridge/bond/VLAN settings survive?

`--static-ip` rewrites the target ifupdown stanza and may drop options such as MTU, bridge, bond, VLAN and pre-up. For complex networking, avoid `--static-ip` and edit the configuration manually. `--dns-only` only replaces `dns-nameservers`.

### 10. Why is hosts-only the default?

To avoid breaking networking on unattended or remote machines. Network changes are explicit via `--static-ip` or `--dns-only`.

### 11. Does `--yes` choose a snapshot automatically?

No. It only auto-confirms the VM warning and network-change confirmation. Use `--no-snapshot` for automation.

### 12. Why does `--dry-run` not ask for IP/DNS?

It does not apply network changes, so it does not collect those values. It still shows the selected network mode/backend and the proposed hosts diff.

### 13. How do I uninstall or restore?

Restore the hosts backup:

```bash
sudo cp /etc/hosts.github520-backup.<timestamp>.<pid> /etc/hosts
```

Or delete the block:

```bash
sudo sed -i '/# GitHub520 Host Start/,/# GitHub520 Host End/d' /etc/hosts
```

Restore network configuration from `/var/backups/github520-*`.

### 14. Why is the output English?

Many TTYs and rescue environments cannot render Chinese correctly. This README provides Chinese documentation; runtime logs remain English.

## Disclaimer

This project is not affiliated with GitHub520. Use it at your own risk. Always keep backups and test on a non-critical machine first.
