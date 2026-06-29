# PetaLinux WSL Install 2018.3 Attempt

Date: 2026-06-29
Cycle ID: petalinux-wsl-install-2018.3

## Objective

Install PetaLinux 2018.3 in WSL Ubuntu 22.04 so `petalinux` commands work and
match the existing Vivado/SDK 2018.3 toolchain.

## Current result

Blocked before installation. The Linux PetaLinux installer is not present
locally, and the official AMD/Xilinx download requires the AMD account download
flow.

## Confirmed environment

| Check | Result |
| --- | --- |
| WSL distro | `Ubuntu-22.04`, WSL2 |
| WSL OS | Ubuntu 22.04.5 LTS |
| WSL user | `root` |
| WSL `HOME` during explicit root commands | `/root` |
| Free space | 908G available on `/` and `/opt` |
| Existing PetaLinux command | Not found |
| Existing `/opt/Xilinx` | Vivado/SDK 2018.3 present |
| `/opt/xilinx-installer-2018.3` | Present, but not used; this is not the Linux PetaLinux `.run` installer |

## Download checks

Requested installer filename:

```text
petalinux-v2018.3-final-installer.run
```

Manual AMD/Xilinx account URL:

```text
https://account.amd.com/en/forms/downloads/xef.html?filename=petalinux-v2018.3-final-installer.run
```

Legacy Xilinx URL tested:

```text
https://www.xilinx.com/member/forms/download/xef.html?filename=petalinux-v2018.3-final-installer.run
```

Observed result:

```text
HTTP/1.1 301 Moved Permanently
Location: https://account.amd.com/en/forms/downloads/xef.html?filename=petalinux-v2018.3-final-installer.run
```

The redirect confirms the requested filename is recognized by the legacy
Xilinx download path, but the final AMD account form did not return installer
bytes through non-interactive `curl`.

## Proxy checks

Initial attempt failed because Clash bound only to Windows loopback. This has
been fixed: `allow-lan: true` set in the Clash config, clash-meta restarted,
now listening on `0.0.0.0:7890`.

| Endpoint from WSL | Result (after fix) |
| --- | --- |
| `http://172.27.96.1:7890` | **works** — google.com returns 302 |
| `http://127.0.0.1:7890` | works from Windows side only |

WSL proxy is now functional. The Windows host IP for WSL is `172.27.96.1`.
Use `export http_proxy=http://172.27.96.1:7890 https_proxy=http://172.27.96.1:7890`
in WSL before any network operation requiring the proxy.

## Installation status

Not run. No files were installed under `/opt/petalinux` or any other PetaLinux
install directory.

## Blocker

The PetaLinux 2018.3 installer (`petalinux-v2018.3-final-installer.run`, ~2-3GB)
is not present on this machine. The official AMD download page requires an
AMD/Xilinx account login through a browser form — non-interactive download via
curl is not possible. The user is currently remote and cannot perform the
browser login.

## Next action (when user is back at the machine)

1. Open in browser and login with AMD account:

```text
https://account.amd.com/en/forms/downloads/xef.html?filename=petalinux-v2018.3-final-installer.run
```

2. Download to one of:

```text
E:\tmp\petalinux-v2018.3-final-installer.run
C:\Users\中二哲人\Downloads\petalinux-v2018.3-final-installer.run
```

3. Copy into WSL and install:

```bash
export HOME=/root
export http_proxy=http://172.27.96.1:7890
export https_proxy=http://172.27.96.1:7890
cp /mnt/c/Users/中二哲人/Downloads/petalinux-v2018.3-final-installer.run /root/
cd /root
chmod +x petalinux-v2018.3-final-installer.run
./petalinux-v2018.3-final-installer.run /opt/petalinux-v2018.3
source /opt/petalinux-v2018.3/settings.sh
petalinux --version
```

4. Verify `petalinux --version` prints 2018.3, then close this cycle.

## Board action

None. This cycle changes host tooling only.

