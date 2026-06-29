# PetaLinux WSL Install 2018.3 Result

Date: 2026-06-29
Cycle ID: petalinux-wsl-install-2018.3

## Outcome

**PASSED.** PetaLinux 2018.3 is installed in WSL Ubuntu 22.04 and the core
PetaLinux commands are available after sourcing the installed settings script.

Install path:

```text
/opt/petalinux-v2018.3
```

Verified commands:

```text
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-build
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-create
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-config
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-package
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-util
```

Version evidence:

```text
settings.sh exports PETALINUX_VER=2018.3
```

PetaLinux 2018.3 does not provide a top-level `petalinux --version` command.
The cycle's original closure wording was inaccurate; the valid verification is
`settings.sh` plus the versioned 2018.3 command suite above.

## Installer

Downloaded file:

```text
C:/Users/中二哲人/Downloads/petalinux-v2018.3-final-installer.run
Size: 7,289,606,083 bytes
Copied to WSL: /home/petalinux/petalinux-v2018.3-final-installer.run
```

The installer must not be run as root. The first root attempt failed with:

```text
ERROR: Exiting Installer: Cannot install as root user !
```

Final install user:

```text
Linux user: petalinux
Home: /home/petalinux
Target directory owner: petalinux:petalinux
```

## Host Compatibility Work

WSL host:

```text
Ubuntu 22.04.5 LTS, WSL2
```

PetaLinux 2018.3 warns that this is not a supported OS, but the installer and
command environment are usable after compatibility fixes.

Installed dependency groups:

```text
net-tools diffstat chrpath socat xterm autoconf libtool unzip texinfo
zlib1g-dev gcc-multilib build-essential libsdl1.2-dev libglib2.0-dev
libncurses5-dev libssl-dev zlib1g:i386 python2 equivs
```

Compatibility fixes:

```text
dpkg --add-architecture i386
Generated en_US.UTF-8 locale
Created local equivs package: python 2.7.18 depends on python2
/usr/bin/python -> /usr/bin/python2
/bin/sh -> bash
```

Why these were needed:

```text
PetaLinux 2018.3 checks for a Debian package named `python`, which Ubuntu
22.04 no longer provides. It also requires en_US.UTF-8 while installing the
Yocto SDKs, and recommends bash as /bin/sh.
```

## Installation Command

The successful install used a clean non-root environment:

```bash
runuser -u petalinux -- bash -lc \
  "export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
   cd /home/petalinux && \
   yes y | ./petalinux-v2018.3-final-installer.run \
     --log /home/petalinux/petalinux_installation_log \
     /opt/petalinux-v2018.3"
```

The installer log ends with:

```text
INFO: PetaLinux SDK has been installed to /opt/petalinux-v2018.3/.
```

Installed size:

```text
13G /opt/petalinux-v2018.3
```

## Verification Command

Use a clean environment to avoid Windows PATH entries with spaces and
parentheses leaking into WSL shell parsing:

```bash
runuser -u petalinux -- env -i \
  HOME=/home/petalinux USER=petalinux LOGNAME=petalinux SHELL=/bin/bash \
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/usr/local/bin:/usr/bin:/bin \
  bash -lc '
    source /opt/petalinux-v2018.3/settings.sh
    set | grep "^PETALINUX"
    command -v petalinux-build
    command -v petalinux-create
    command -v petalinux-config
    command -v petalinux-package
    command -v petalinux-util
    petalinux-create --help | head -20
  '
```

Verification output included:

```text
PetaLinux environment set to '/opt/petalinux-v2018.3'
PETALINUX=/opt/petalinux-v2018.3
PETALINUX_VER=2018.3
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-build
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-create
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-config
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-package
/opt/petalinux-v2018.3/tools/common/petalinux/bin/petalinux-util
petalinux-create             (c) 2005-2018 Xilinx, Inc.
```

## Accepted Warnings

These warnings remain and are accepted for this stage:

```text
WARNING: This is not a supported OS
WARNING: No tftp server found
environment: line 312/316: Ubuntu version parse warning
```

Reason:

```text
The project needs local project generation/build first. TFTP is not required
for the next cycle. The unsupported-OS and version-parse warnings are recorded
risks for Ubuntu 22.04, not current hard failures.
```

## Board Action

None. This cycle only changed host WSL tooling.

## Next Cycle

Open a new implementation cycle to create a minimal PetaLinux project from the
VDMA HDMI hardware design, then prove the generated image can boot and preserve
the already-confirmed Linux Ethernet path.
