#!\bin\bash
#Installs GPU Burn and runs GPU-brun and coolgpus Test


echo "cloning repository"
git clone https://github.com/wilicc/gpu-burn
sleep 1

cd gpu-burn

echo "building docker container..."
sudo docker build -t gpu_burn .
sleep 1


echo "Please enter number of seconds for GPU burn test: "
read option
echo "running GPU-burn test for ${option} seconds"
sudo docker run --rm --gpus all gpu_burn ./gpu_burn ${option}


