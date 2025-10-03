#/bin/bash
sudo -v
if [ "$EUID" -ne 0 ]; then
    echo "Re-running script as root..."
    exec sudo bash "$0" "$@"
fi

NVIDIA_DRIVER_PACKAGE="nvidia-driver-535-server"
GPU_BURN_SECONDS=90


## install pre-requisites
echo "Installing prerequisites..."
apt update && apt install -y curl ca-certificates python3-pip git&
wait

## verify runlevel 3 is default(multi-user.target)
systemctl set-default multi-user.target

## add nvidia repo
echo "Adding NVIDIA package repositories..."
. /etc/os-release #source the file to get VERSION_ID
UBUNTU_VERSION=$(echo "$VERSION_ID" | tr -d '.')
curl -s -L "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb" -o cuda-keyring.deb
dpkg -i cuda-keyring.deb &
wait

## Add docker repo
echo "Adding Docker package repositories..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc &
wait
chmod a+r /etc/apt/keyrings/docker.asc
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null &
wait

## update package lists
echo "Updating package lists..."
apt update && apt upgrade -y &
wait

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
apt -y install ${NVIDIA_DRIVER_PACKAGE} nvidia-settings nvidia-container-toolkit&
wait
nvidia-ctk runtime configure --runtime=docker &
wait

## install coolgpus
echo "Installing coolgpus from PyPI..."
pip install coolgpus

## install gpu-burn
echo "Installing GPU Burn..."
#snap install gpu-burn --edge
git clone https://github.com/wilicc/gpu-burn &
wait
cd gpu-burn
sudo docker build -t gpu_burn . &
wait
cd ~


# prepare for tests
systemctl isolate multi-user.target
systemctl restart docker

$(which coolgpus) --kill --speed 99 99 --kill &
sleep 10


## run gpu-burn test
echo "Running GPU Burn test for ${GPU_BURN_SECONDS} seconds..."
#the following need to run in tmux windows
tmux new-session -d -s gpu_test "docker run --rm --gpus all gpu_burn ./gpu_burn -d ${GPU_BURN_SECONDS}"
tmux split-window -h -t gpu_test "watch -n 1 nvidia-smi"
tmux attach-session -t gpu_test

