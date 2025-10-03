#!\bin\bash
#runs coolgpus


cd /usr/local/bin

echo executing coolgpus
echo running GPU fans at 99 speed 

sudo ./coolgpus --speed 99 99

echo "coolgpus enabled - execute GPU_Burn_Test.sh"
sleep 1



