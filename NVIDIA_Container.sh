#!\bin\bash
#installs and configures NVIDIA container toolkit for docker



#configure production repository
echo "Installing NVIDIA container Toolkit" 

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sleep 1

. /etc/os-release
UBUNTU_VERSION=$(echo "$VERSION_ID" | tr -d '.')
curl -s -L "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${UBUNTU_VERSION}/x86_64/cuda-keyring_1.1-1_all.deb" -o cuda-keyring.deb
sudo dpkg -i cuda-keyring.deb
sudo apt update

sleep 1

sudo apt install -y nvidia-container-toolkit
sleep 1

#configure docker

sudo nvidia-ctk runtime configure --runtime=docker
sleep 1


sudo systemctl restart docker
sleep 1


