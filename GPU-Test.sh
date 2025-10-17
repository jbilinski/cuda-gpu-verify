#!/bin/bash
# gpu-test.sh
# A script to set up and run a GPU stress test on Ubuntu systems with NVIDIA GPUs.

sudo -v
if [ "$EUID" -ne 0 ]; then
    printf "Re-running script as root...\n"
    exec sudo bash "$0" "$@"
fi

NVIDIA_DRIVER_PACKAGE="nvidia-driver-535-server"
GPU_BURN_SECONDS=90
SMI_LOG_PATH="$(getent passwd "$SUDO_USER" | cut -d: -f6)"


# Common log file with timestamp
LOG_FILE="${SMI_LOG_PATH%/}/gpu-test.log"

# Common logging function
log_to_file() {
    local log_type="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file with timestamp and type
    echo "[$timestamp] [$log_type] $message" >> "$LOG_FILE"
    
    # Also output to console for important messages
    case "$log_type" in
        "INFO"|"ERROR"|"WARNING")
            echo "[$log_type] $message"
            ;;
    esac
}

# Convenience functions
log_info() { log_to_file "INFO" "$@"; }
log_error() { log_to_file "ERROR" "$@"; }
log_warning() { log_to_file "WARNING" "$@"; }
log_debug() { log_to_file "DEBUG" "$@"; }

# Function to log command output to file
log_command_output() {
    local command_description="$1"
    shift
    local command="$*"
    
    log_to_file "CMD_START" "Executing: $command_description"
    echo "[$command_description - $(date '+%Y-%m-%d %H:%M:%S')]" >> "$LOG_FILE"
    echo "Command: $command" >> "$LOG_FILE"
    echo "--- Output Start ---" >> "$LOG_FILE"
    
    # Execute command and capture both stdout and stderr
    if eval "$command" >> "$LOG_FILE" 2>&1; then
        log_to_file "CMD_SUCCESS" "$command_description completed successfully"
    else
        log_to_file "CMD_ERROR" "$command_description failed with exit code $?"
    fi
    
    echo "--- Output End ---" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

gput-prep() {
    ## install pre-requisites
    printf "Installing prerequisites...\n"
    apt update && apt install -y curl ca-certificates python3-pip git tmux & wait

    ## add nvidia repo
    printf "Adding NVIDIA package repositories...\n"
    . /etc/os-release #source the file to get VERSION_ID
    UBUNTU_VERSION=$(echo "$VERSION_ID" | tr -d '.')
    curl -s -L "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb" -o cuda-keyring.deb
    dpkg -i cuda-keyring.deb & wait

    ## Add docker repo
    printf "Adding Docker package repositories...\n"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc & wait
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null & wait

    ## update package lists
    printf "Updating package lists...\n"
    apt update && apt upgrade -y & wait
}



gput-install() {
    ## Uninstall old docker versions
    printf "Removing old Docker versions, if any...\n"
    snap remove --purge docker
    apt remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc &
    wait

    ## Install docker
    printf "Installing Docker...\n"
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &
    wait

    ## remove any existing nvidia drivers
    printf "Removing existing NVIDIA drivers and modules, if any...\n"
    apt remove --purge '^nvidia-.*' -y &
    wait
    printf "blacklist nouveau" | tee /etc/modprobe.d/blacklist-nouveau.conf
    printf  "options nouveau modeset=0" | tee -a /etc/modprobe.d/blacklist-nouveau.conf
    update-initramfs -u &
    wait

    ## install nvidia packages
    printf "Installing NVIDIA driver and related packages...\n"
    apt -y install ${NVIDIA_DRIVER_PACKAGE} nvidia-settings nvidia-container-toolkit &
    wait
    nvidia-ctk runtime configure --runtime=docker &
    wait

    ## install coolgpus
    printf "Installing coolgpus from PyPI...\n"
    pip install coolgpus

    ## install gpu-burn
    printf "Installing GPU Burn...\n"
    #snap install gpu-burn --edge
    cd ~/cuda-gpu-verify
    git submodule update --init --recursive #pull the gpu-burn repo
    chmod +x ~/cuda-gpu-verify/GPU-Test.sh #make sure the script stays executable
    cd ~/cuda-gpu-verify/gpu-burn/
    docker build -t gpu_burn . &
    wait
    cd ~
}

#TODO add check for nvidia-smi and coolgpus commands
gput-checkdependencies() {
    printf "\rChecking for required dependencies...\n"
    local dependencies=(docker nvidia-smi coolgpus)
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            printf "\rError: $cmd is not installed. Please run the install step first.\n"
            exit 1
        fi
    done
    printf "\rAll required dependencies are installed."
}

gput-test() {
    log_info "Starting GPU test sequence"
    
    ## verify runlevel 3 is default(multi-user.target)
    systemctl set-default multi-user.target

    # prepare for tests
    systemctl isolate multi-user.target # Kill graphical session if any prior to coolgpus and gpu-burn
    systemctl restart docker
    
    # reset GPUs
    nvidia-smi -r

    log_info "Starting coolgpus with 99% fan speed"
    setsid "$(command -v coolgpus)" --kill --speed 99 99 --kill >/dev/null 2>&1 < /dev/null &
    for i in $(seq 16 -1 1); do
        printf "\rWaiting %2d seconds for coolgpus... " "$i"
        sleep 1
    done
    printf "\rcoolgpus fan settings applied               \n"
    
    log_info "Logging initial GPU states"
    log_command_output "Initial GPU PCI States" "nvidia-smi -q | grep -A 16 -w 'PCI'"
    log_command_output "Initial GPU Fan States" "nvidia-smi -q | grep -A 1 -w 'Fan Speed'"

    ## run gpu-burn test
    clear
    printf "Running GPU Burn test for ${GPU_BURN_SECONDS} seconds...\n"
    log_info "Starting GPU Burn test for ${GPU_BURN_SECONDS} seconds"
    sleep 2
    
    #the following need to run in tmux windows
    tmux new-session -d -s gpu_test "docker run --rm --gpus all gpu_burn ./gpu_burn -d ${GPU_BURN_SECONDS}"
    tmux split-window -h -t gpu_test "watch -b -c -n 5 nvidia-smi"
    # detached tmux window that logs nvidia-smi to our common log file
    tmux new-window -t gpu_test -n smi -d "while true; do echo '--- nvidia-smi dmon output at $(date) ---' >> '$LOG_FILE'; nvidia-smi dmon -d 8 -c 1 >> '$LOG_FILE' 2>&1; sleep 8; done"
    (sleep $((GPU_BURN_SECONDS + 30)); tmux kill-session -t gpu_test) &
    tmux attach-session -t gpu_test
    
    log_info "GPU Burn test completed"
    printf "GPU Burn test completed. All logs saved to: ${LOG_FILE}\n"
    
    log_info "Logging final GPU states"
    log_command_output "Final GPU PCI States" "nvidia-smi -q | grep -A 16 -w 'PCI'"
    log_command_output "Final GPU Fan States" "nvidia-smi -q | grep -A 1 -w 'Fan Speed'"
    
    log_info "GPU test sequence completed. Log file: ${LOG_FILE}"
}

show_usage() {
    cat <<EOF
Usage: $0 [prep|install|test|all|-h|--help]

Commands:
  prep      Run only preparation steps (gput-prep)
  install   Run only installation steps (gput-install)
  test      Run only test steps (gput-test)
  all       Run prep, install and test (same as no args)
  -h, --help  Show this help
EOF
}

if [ $# -ge 1 ]; then
    case "$1" in
        prep)
            gput-prep
            exit 0
            ;;
        install)
            gput-install
            exit 0
            ;;
        test)
            gput-test
            exit 0
            ;;
        all)
            gput-prep
            gput-install
            gput-test
            exit 0
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown command: $1"
            show_usage
            exit 2
            ;;
    esac
fi



