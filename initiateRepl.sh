#!/bin/sh
#
# initiateRepl.sh 
#       Copy and initiate MySQL replication
#
# Created by Daniel Gullin <daniel.gullin@ballou.se>
#
# 130830: Version 0.1
#       Created first version
# 130903: Version 0.2
# 130915: Version 0.3
#
# REQUIREMENTS
#
# * Setup LVM for /var/lib/mysql
# * SSH keys
# * Replication user in MySQL
# * Same MySQL version of both master and slave (of course)
#
# !!! TIPS !!!
# 
# * When you do a full sync, you must change password for debian-sys-maint on the server that is slave.
# * If you have master-master replication I think you have to stop the replication first.
#
############################################################

# What DB should we start replicate
SYNCDB="DB" 
# IP of the master database server
MASTER="MASTERIP"
# IP of the slave database server
SLAVE="SLAVEIP"
# What user should we use to setup the replication ?
MYSQLUSER="root"
# Some passwords
MYSQL_MASTER_PASSWD='MASTERDB_PASSWORD'
MYSQL_SLAVE_PASSWD="SLAVEDB_PASSWORD"
# Replication user
REPLUSER="repl"
REPLPASSWD="USERREPL_PASSWORD"

# LVS variables, don´t bother :)
VG=vg_mysql
LV=mysqldata
LVSNAPNAME="mysql_snap"

############################################################
### NO MODIFY BELOW THIS ###################################
############################################################

tabs -12

MYSQL="/usr/bin/mysql"
RSYNC="/usr/bin/rsync"
SYNCDB="ibdata1 ib_logfile0 ib_logfile1 "$SYNCDB 

clear
echo ""
printf "\033[34m --- INITIATE AND COPY MYSQL DATA TO $SLAVE ---\033[0m\n"
printf " \n Check \033[36merror.log\033[0m for yummy detailes\n\n"
date
echo ""
if [ -f error.log ] ; then
        rm error.log
fi

printf " + Check if /mysql-snap is mounted"
mountpoint /mysql-snap > error.log 2>&1
if [ $? -eq 0 ]; then
        printf "\n    (/mysql-snap exist and we remove it)!!"
        umount /mysql-snap; lvremove -f /dev/$VG/$LVSNAPNAME > error.log 2>&1        
        if [ $? -eq 0 ]; then
      printf "\t\t\t\t\033[32m[ok]\033[0m\n"   
    else
      printf "\t\t\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi   

          else 
          printf "\t\t\033[32m[ok]\033[0m\n"   
fi

# Flush & Lock
printf " + Flush MySQL tables with Read Lock"
$MYSQL -hlocalhost -u$MYSQLUSER -p$MYSQL_MASTER_PASSWD -Bse "FLUSH TABLES WITH READ LOCK" > error.log 2>&1
if [ $? -eq 0 ]; then
      printf "\t\t\033[32m[ok]\033[0m\n"   
   else
      printf "\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi   

# Take LVM snapshot
printf " + Creating snapshot"
lvcreate --name=$LVSNAPNAME --snapshot --size=1024M /dev/$VG/$LV > error.log 2>&1
if [ $? -eq 0 ]; then
      printf "\t\t\t\t\033[32m[ok]\033[0m\n"
      
   else
      printf "\t\t\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi

# Check Master file and position
printf " + Check Master file and position\n"
MASTERLOGFILE=`$MYSQL -hlocalhost -u$MYSQLUSER -p$MYSQL_MASTER_PASSWD -Bse "SHOW MASTER STATUS\G"|grep File| awk '{print $2}'`
MASTERPOS=`$MYSQL -hlocalhost -u$MYSQLUSER -p$MYSQL_MASTER_PASSWD -Bse "SHOW MASTER STATUS\G"|grep Position| awk '{print $2}'`

# Unlock 
printf " + Unlock MySQL tables"
$MYSQL -hlocalhost -u$MYSQLUSER -p$MYSQL_MASTER_PASSWD -Bse "UNLOCK TABLES" > error.log 2>&1
if [ $? -eq 0 ]; then
      printf "\t\t\t\t\033[32m[ok]\033[0m\n"
     
   else
      printf "\t\t\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi

# Mount the snapshot
printf " + Mount the snapshot to /mysql-snap" 
mount  /dev/$VG/$LVSNAPNAME /mysql-snap > error.log 2>&1
if [ $? -eq 0 ]; then
      printf "\t\t\033[32m[ok]\033[0m\n"
      
   else
      printf "\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi

# Stop Mysql on Slave
printf " + Stop remote mysql server"

ssh root@$SLAVE 'service mysql stop' > error.log 2>&1
        if [ $? -eq 0 ]; then
                printf "\t\t\t\033[32m[ok]\033[0m\n"      
        else
                printf "\t\t\t\033[31m[failed]\033[0m\n"
                exit 1
        fi   


# Delete /var/lib/mysql
for db in $SYNCDB; do
        printf " + Delete $db"
        ssh root@$SLAVE "rm -Rf /var/lib/mysql/mysqldata/$db" > error.log 2>&1

        if [ $? -eq 0 ]; then
      printf "\t\t\t\t\033[32m[ok]\033[0m\n"  
        else
      printf "\t\t\t\033[31m[failed]\033[0m\n"
      exit 1
        fi  
done

# Rsync to slave
for dir in $SYNCDB; do
        printf " + Copying /mysql-snap/$dir"
        #$RSYNC -e ssh -avz /mysql-snap/mysqldata/$dir $SLAVE:/var/lib/mysql/mysqldata > error.log 2>&1
        $RSYNC -av /mysql-snap/mysqldata/$dir $SLAVE:/var/lib/mysql/mysqldata > error.log 2>&1
        if [ $? -eq 0 ]; then
      printf "\t\t\t\033[32m[ok]\033[0m\n"
     
   else
      printf "\t\t\t\033[31m[failed]\033[0m\n\n"
      exit 1
   fi
done

# Start Mysql on Slave
sleep 1
printf " + Start remote MariaDB"
ssh root@$SLAVE 'service mysql start' > error.log 2>&1;
if [ $? -eq 0 ]; then
      printf "\t\t\t\033[32m[ok]\033[0m\n"
      
   else
      printf "\t\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi

# Remove local snapshot
printf " + Unmount and remove local snapshot"
umount /mysql-snap > error.log 2>&1
lvremove -f /dev/$VG/$LVSNAPNAME > error.log 2>&1
if [ $? -eq 0 ]; then
      printf "\t\t\033[32m[ok]\033[0m\n"
      
   else
      printf "\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi

#
printf " + Activating the master-slave \n"
printf "      -STOP SLAVE"
$MYSQL -h $SLAVE -u$MYSQLUSER -p$MYSQL_SLAVE_PASSWD -e "STOP SLAVE" > error.log 2>&1
if [ $? -eq 0 ]; then
      printf "\t\t\t\t\033[32m[ok]\033[0m\n"
      
   else
      printf "\t\t\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi
 printf "      -CHANGE MASTER..."  
 sleep 1
$MYSQL -h $SLAVE -u$MYSQLUSER -p$MYSQL_SLAVE_PASSWD -e "CHANGE MASTER TO MASTER_HOST='$MASTER',MASTER_USER='$REPLUSER',MASTER_PASSWORD='$REPLPASSWD',MASTER_LOG_FILE='$MASTERLOGFILE',MASTER_LOG_POS=$MASTERPOS;" > error.log 2>&1
if [ $? -eq 0 ]; then
      printf "\t\t\t\033[32m[ok]\033[0m\n"
      
   else
      printf "\t\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi
printf "      -START SLAVE"
sleep 1
$MYSQL -h $SLAVE -u$MYSQLUSER -p$MYSQL_SLAVE_PASSWD -e "START SLAVE;"
if [ $? -eq 0 ]; then
      printf "\t\t\t\t\033[32m[ok]\033[0m\n"
      
   else
      printf "\t\t\t\t\033[31m[failed]\033[0m\n"
      exit 1
   fi

echo ""
sleep 2
   
# Checking
printf "Status: "
$MYSQL -h $SLAVE -u$MYSQLUSER -p$MYSQL_SLAVE_PASSWD -e "show slave status\G;"|grep Slave_IO_State| sed -e 's/[^:]*://'

echo ""
date
echo ""
