#! /bin/bash

######## Parameters ########
apptype=$1
echo "apptype = "$apptype" Running on "`date +'%Y%m%d%H%M'`

######## Backup KAP & Kyanalyzer & Zeppelin ########
kap_dir="/usr/local/kap/kap-*"
kyanalyzer_dir="/usr/local/kap/kyanalyzer-server"
zeppelin_dir="/usr/local/zeppelin"

base_backup_dir="/kycloud/backup"
kap_backup_dir=$base_backup_dir/kap
kyanalyzer_backup_dir=$base_backup_dir/kyanalyzer
zeppelin_backup_dir=$base_backup_dir/zeppelin

backupKAP() {
    hdfs dfs -mkdir -p $kap_backup_dir
    hdfs dfs -put -f $kap_dir/conf $kap_backup_dir
}

backupKyAnalyzer() {
	hdfs dfs -rm -r -f -skipTrash $kyanalyzer_backup_dir
    hdfs dfs -mkdir -p $kyanalyzer_backup_dir
    hdfs dfs -put -f $kyanalyzer_dir/data $kyanalyzer_backup_dir/data
    hdfs dfs -put -f $kyanalyzer_dir/repository $kyanalyzer_backup_dir/repository
    hdfs dfs -put -f $kyanalyzer_dir/conf $kyanalyzer_backup_dir/conf
}

backupZeppelin() {
    hdfs dfs -mkdir -p $zeppelin_backup_dir
    hdfs dfs -put $zeppelin_dir $zeppelin_backup_dir
}

main() {
    case "$apptype" in
        KAP+KyAnalyzer+Zeppelin)
            backupKAP
            backupKyAnalyzer
# Not running Zeppelin backup
#            backupZeppelin
            ;;
        KAP+KyAnalyzer)
            backupKAP
            backupKyAnalyzer
            ;;
        KAP)
            backupKAP
            ;;
        *)
            echo "Not Supported APP Type!"
            exit 1
            ;;
    esac
}

##############################
if [ "$(id -u)" != "0" ]; then
    echo "[ERROR] The script has to be run as root."
    exit 1
fi

main
