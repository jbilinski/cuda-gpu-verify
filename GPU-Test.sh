#!/bin/bash
# gpu-test.sh
# A script to set up and run a GPU stress test on Ubuntu systems with NVIDIA GPUs.

sudo -v
if [ "$EUID" -ne 0 ]; then
    echo "Re-running script as root..."
    exec sudo bash "$0" "$@"
fi

NVIDIA_DRIVER_PACKAGE="nvidia-driver-535-server"
GPU_BURN_SECONDS=90
SMI_LOG_PATH=$HOME


gput-prep() {
    ## install pre-requisites
    echo "Installing prerequisites..."
    apt update && apt install -y curl ca-certificates python3-pip git tmux & wait

    ## add nvidia repo
    echo "Adding NVIDIA package repositories..."
    . /etc/os-release #source the file to get VERSION_ID
    UBUNTU_VERSION=$(echo "$VERSION_ID" | tr -d '.')
    curl -s -L "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb" -o cuda-keyring.deb
    dpkg -i cuda-keyring.deb & wait

    ## Add docker repo
    echo "Adding Docker package repositories..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc & wait
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null & wait

    ## update package lists
    echo "Updating package lists..."
    apt update && apt upgrade -y & wait
}



gput-install() {
    ## Uninstall old docker versions
    echo "Removing old Docker versions, if any..."
    snap remove --purge docker
    apt remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc &
    wait

    ## Install docker
    echo "Installing Docker..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin &
    wait

    ## remove any existing nvidia drivers
    echo "Removing existing NVIDIA drivers and modules, if any..."
    apt remove --purge '^nvidia-.*' -y &
    wait
    echo "blacklist nouveau" | tee /etc/modprobe.d/blacklist-nouveau.conf
    echo "options nouveau modeset=0" | tee -a /etc/modprobe.d/blacklist-nouveau.conf
    update-initramfs -u &
    wait

    ## install nvidia packages
    echo "Installing NVIDIA driver and related packages..."
    apt -y install ${NVIDIA_DRIVER_PACKAGE} nvidia-settings nvidia-container-toolkit &
    wait
    nvidia-ctk runtime configure --runtime=docker &
    wait

    ## install coolgpus
    echo "Installing coolgpus from PyPI..."
    pip install coolgpus

    ## install gpu-burn
    echo "Installing GPU Burn..."
    #snap install gpu-burn --edge
    cd ~/cuda-gpu-verify/gpu-burn/
    sudo docker build -t gpu_burn . &
    wait
    cd ~
}

#TODO add check for nvidia-smi and coolgpus commands
gput-checkdependencies() {
    echo "Checking for required dependencies..."
    local dependencies=(docker nvidia-smi coolgpus)
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: $cmd is not installed. Please run the install step first."
            exit 1
        fi
    done
    echo "All required dependencies are installed."
}

gput-test() {
    ## verify runlevel 3 is default(multi-user.target)
    systemctl set-default multi-user.target

    # prepare for tests
    systemctl isolate multi-user.target # Kill graphical session if any prior to coolgpus and gpu-burn
    systemctl restart docker

    setsid "$(command -v coolgpus)" --kill --speed 99 99 --kill >/dev/null 2>&1 < /dev/null &
    echo "Waiting 16 seconds for coolgpus to set persistence mode and clocks..."
    for i in $(seq 16 -1 1); do
        printf "\rWaiting %2d seconds for coolgpus... " "$i"
        sleep 1
    done
    printf "\rcoolgpus fan settings applied               \n"


    ## run gpu-burn test
    clear
    echo "Running GPU Burn test for ${GPU_BURN_SECONDS} seconds..."
    sleep 2
    #the following need to run in tmux windows
    tmux new-session -d -s gpu_test "docker run --rm --gpus all gpu_burn ./gpu_burn -d ${GPU_BURN_SECONDS}"
    tmux split-window -h -t gpu_test "nvidia-smi -l 1"
    tmux background -t gpu_test "nvidia-smi -l 5 -f ${SMI_LOG_PATH%/}/nvidia-smi-$(date +%Y%m%d-%H%M%S).log &"
    (sleep $((GPU_BURN_SECONDS + 60)); tmux kill-session -t gpu_test) &
    tmux attach-session -t gpu_test
    echo "GPU Burn test completed. Status in nvidia-smi log file under ${SMI_LOG_PATH}."
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



