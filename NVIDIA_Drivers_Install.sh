#!/bin/bash


sudo apt-get update 
apt upgrade -y &



#remove docker with snap, reinstall using apt
sudo snap remove --purge docker
sudo apt install docker.io
sudo apt install docker
clear

#install nvidia 535 server
sudo apt -y install nvidia-driver-535-server

sleep 1

#install nvidia settings
sudo apt install nvidia-settings

sleep 1

#blacklist the Nouveau driver so it doesn't initialize:
sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
sleep 1

cat /etc/modprobe.d/blacklist-nvidia-nouveau.conf
sleep 1
clear

#update the kernel to reflect changes:
echo "updating initramfs..."
sleep 1
sudo update-initramfs -u
clear


#test if nvidia-smi output works
nvidia-smi


echo "NVIDIA 535 Server installed"

#install pip and coolgpus 
sudo apt install python3-pip
sleep 1

pip install coolgpus
sleep 1

#kill displays
sudo systemctl set-default multi-user.target

echo "coolgpus installed"
echo "Executing NVIDIA_Container.sh"
sleep 1

sudo bash NVIDIA_Container.sh
