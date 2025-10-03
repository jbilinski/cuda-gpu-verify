# gpu-test.sh — README

## Overview

This script automates preparing an Ubuntu system for NVIDIA GPU stress testing and then runs a GPU burn-in under tmux while monitoring with nvidia-smi.

At a high level it will:

- Configure the system to boot to multi-user (non-GUI) mode and switch to it immediately.
- Add NVIDIA CUDA and Docker APT repositories; update/upgrade packages.
- Remove any existing NVIDIA drivers and Nouveau, regenerate initramfs.
- Install an NVIDIA driver (default: `nvidia-driver-535-server`) and NVIDIA Container Toolkit.
- Install Docker and configure it to use the NVIDIA runtime.
- Install `coolgpus` and set GPU fans to maximum during the test.
- Build the GPU Burn Docker image and run the test in tmux alongside a live `nvidia-smi` monitor.

Use this on a dedicated Linux host with an NVIDIA GPUs when you want to validate GPU stability and thermals under load.

## Important warnings

- This script modifies system boot behavior: it sets the default target to `multi-user.target` (no GUI) and switches to it immediately. It's not intended to run on a system with x11/Wayland in use.
- It removes existing NVIDIA drivers and blacklists Nouveau. A reboot may be required for all changes to take effect, especially if drivers were changed.
- It *attempts to* set GPU fans to high speed via `coolgpus` during the test. This is intentional for thermal headroom.

## Tested/assumed environment

- OS: Ubuntu Server LTS (systemd-based; `apt` available).
- NVIDIA GPUs present and visible to the system.
- Internet access to reach NVIDIA and Docker repositories and GitHub.
- Sudo/root privileges. The script self-elevates with `sudo` if not run as root.

## What the script does (step-by-step)

1. Elevates to root with sudo.
2. Installs prerequisites: curl, CA certs, Python pip, git.
3. Sets default boot target to multi-user (no GUI).
4. Adds NVIDIA CUDA repo based on your Ubuntu version and installs its keyring.
5. Adds Docker’s official APT repo and GPG key.
6. Updates and upgrades packages.
7. Removes old Docker packages; installs Docker Engine and Compose plugin.
8. Purges any existing `nvidia-*` packages; blacklists Nouveau and updates initramfs.
9. Installs the driver package `nvidia-driver-535-server`, `nvidia-settings`, and `nvidia-container-toolkit`.
10. Configures the NVIDIA runtime for Docker using `nvidia-ctk`.
11. Installs `coolgpus` from PyPI.
12. Clones `gpu-burn` and builds a Docker image named `gpu_burn`.
13. Switches to multi-user target and restarts Docker.
14. Sets GPU fans to high via `coolgpus` for the duration of the test.
15. Starts a tmux session with two panes:

- Left: `docker run --rm --gpus all gpu_burn ./gpu_burn -d <seconds>`
- Right: `watch -n 1 nvidia-smi`


## Usage


1. Make the script executable and run it:

```bash
chmod +x gpu-test.sh
sudo ./gpu-test.sh
```

The script will prompt for sudo if you do not run it with root privileges.

### Configuration

You can adjust two variables at the top of the script:

- `NVIDIA_DRIVER_PACKAGE` (default: `nvidia-driver-535-server`)
- `GPU_BURN_SECONDS` (default: `90`)

Example to run a longer test using a different driver:

```bash
NVIDIA_DRIVER_PACKAGE=nvidia-driver-550-server GPU_BURN_SECONDS=600 sudo -E ./GPU-Test.sh
```

The `-E` preserves the environment so the script reads your overridden values.

## During the test (tmux basics)

- The script creates a tmux session named `gpu_test` with two panes.
- To detach from tmux and leave the test running: press `Ctrl-b` then `d`.
- To reattach later:

```bash
tmux attach -t gpu_test
```

## Expected results

- `gpu_burn` consumes the GPU at near 100% for `GPU_BURN_SECONDS`.
- `watch nvidia-smi` shows utilization, temperatures, clocks, and power usage live.
- On completion, the `gpu_burn` container exits and tmux session will remain until you close it.

## Troubleshooting

- tmux not found: install with `sudo apt install -y tmux` and re-run the script.
- `could not select device driver "nvidia"` in Docker: ensure `nvidia-container-toolkit` is installed and `nvidia-ctk runtime configure --runtime=docker` succeeded; restart Docker (`sudo systemctl restart docker`). A reboot may be required after driver changes.
- Secure Boot enabled: unsigned NVIDIA kernel modules may be blocked. Either enroll a MOK/sign the module or disable Secure Boot during testing.
- X/GUI stopped unexpectedly: the script isolates to `multi-user.target`. Use the restore commands above to go back to graphical mode.
- No internet access: repository setup and `git clone` will fail; ensure connectivity or pre-stage packages.

## Cleanup (optional)

 -   
To remove the cloned repo and Docker image:
```bash
rm -rf ~/gpu-burn
sudo docker image rm gpu_burn
```

## Future improvements
 - [ ]TODO: add an option to uninstall everything the script installed.
 - [ ]TODO: implement better error handling and logging throughout the script.
 - [ ]TODO: add support for rebooting with a prompt to continue after reboot.
 - [ ]TODO: add test and setup for OEM fan control utilities ( `ipmitool`,`lm-sensors`, `fancontrol`).