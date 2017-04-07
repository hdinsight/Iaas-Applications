#! /bin/bash

######## Parameters ########
clustername=$1
fileblob=$2
storageAccount=$3
storagePassord=$4


######## Backup KAP & Kyanalyzer & Zeppelin ########
kap_dir="/usr/local/kap/kap-*"
kyanalyzer_dir="/usr/local/kap/kyanalyzer-server"
zeppelin_dir="/usr/local/zeppelin"

mkdir /remote
mount -t cifs //$fileblob/$clustername /remote -o vers=3.0,username=$storageAccount,password=$storagePassord,dir_mode=0777,file_mode=0777
mkdir /remote/kap
mkdir /remote/kyanalyzer
mkdir /remote/zeppelin

cp -r $kap_dir/conf /remote/kap
cp -r $kyanalyzer_dir/repository /remote/kyanalyzer
cp -r $kyanalyzer_dir/data /remote/kyanalyzer
cp -r $zeppelin_dir /remote