#! /bin/bash

######## Parameters ########
clustername="test2"
fileblob="https://testcon1.file.core.windows.net/test1"
storageAccount="testcon1"
storagePassord="iJbGA3Q918Shb776wax+NOw38gxj4Xov4x2BoR9mkFF7XKi6gY6DVH87k14hSubJiYtAxm4DaIljaeI720Enow=="


blobroot=$(hdfs getconf -confKey fs.defaultFS)

######## Backup Hive Tables To Azure Blob ########
databases=($(hive -e "show databases;"))

for db in "${databases[@]}"
do
    tables=($(hive -e "USE $db; SHOW tables;"))
    for table in "${tables[@]}"
    do
        echo "got a $table"
        hive -e "USE $db; EXPORT TABLE $table to '$blobroot/$clustername/$db/$table';"
    done
done

######## Drop All Databases ########
for db in "${databases[@]}"
do
    hive -e "DROP DATABASE IF EXISTS $db CASCADE;"
done

######## Backup KAP & Kyanalyzer & Zeppelin ########
kap_dir="/usr/local/kap/kap-*"
kyanalyzer_dir="/usr/local/kap/kyanalyzer-server"
zeppelin_dir="/usr/local/zeppelin"

mkdir /remote
mount -t cifs //testcon1.file.core.windows.net/$clustername /remote -o vers=3.0,username=$storageAccount,password=$storagePassord,dir_mode=0777,file_mode=0777
mkdir /remote/kap
mkdir /remote/kyanalyzer
mkdir /remote/zeppelin

cp -r $kap_dir/conf /remote/kap
cp -r $kyanalyzer_dir/repository /remote/kyanalyzer
cp -r $kyanalyzer_dir/data /remote/kyanalyzer
cp -r $zeppelin_dir /remote