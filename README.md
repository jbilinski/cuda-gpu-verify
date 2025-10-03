# UbuntuServerDrivers
Bash script for installing specific nvidia drivers for ubuntu. installs NVIDIA 535-server drivers, Nvidia container toolkit.
Installs gpu burn test, and coolgpus and can run them.
Purpose of testing is to run coolgpus and gpu_burn in parallel to stress test servers and check for hardware issues.



# NVIDIA_Drivers_install.sh

Installs docker with apt. Removes docker if installed with snap. Installs Nvidia-535-server
drivers, blacklist nouveau drivers and updates kernel. Runs nvidia-smi so user can see if all gpus are detected. Installs pip, then uses pip to install coolgpus. After finishing all tasks, executes NVIDIA_Container.sh

# NVIDIA_Container.sh
Installs Nvidia container toolkit with apt. Configures production repository, and installs NVIDIA container toolkit packages. Configures container runtime. Restarts docker to reflect changes.

# Coolgpus.sh
Navigates to coolgpus directory, executes coolgpus to run fans at 99 speed. Will continue until this process is terminated.

# GPU_Burn_Test.sh
Clones gpu burn repo, builds docker container. Prompts user to enter number of seconds to run GPU burn. Runs GPU burn for user specified time. 



