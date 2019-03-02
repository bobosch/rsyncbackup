#!/bin/bash
dst="/disk1"

olddir=$dst/`ls -t1 $dst/|grep --invert-match "lost+found"|head -1`
newdir=$dst/`date +%Y-%m-%d`
curdir=$dst/current

rsync_opt="--archive --numeric-ids --progress --relative --exclude-from=/etc/rsyncbackup.exclude"
#rsync_opt="--archive --checksum --numeric-ids --progress --relative --exclude-from=/etc/rsyncbackup.exclude"

log=/tmp/rsyncbackup.log

snapshot=0
fs=`df -T | grep "$dst" | awk '{print $2}'`
if [ "$fs" == "btrfs"  ]; then
	if [ ! -d "$curdir" ]; then
		btrfs subvolume create $curdir
		cp -av --reflink=always $olddir/. $curdir
	fi
	snapshot=1
fi
echo $snapshot>>$log

if [ "$snapshot" == "0" ]; then
	mkdir $newdir
fi

IFS=","
cat /etc/rsyncbackup.csv | while read server files db
do
	IFS=" "

	if [ "${db}" != "" ]; then
		if [ "${db}" == "*" ]; then
			databases="--all-databases"
		else
			databases="--databases ${db}"
		fi
		mysql_opt="--defaults-file=/etc/mysql/debian.cnf ${databases}"
	fi


	if [ "$snapshot" == "1" ]; then
		dest_dir=$curdir/${server}
		rsync_par="--delete --log-file=$dest_dir/rsync.log"

		rm "$dest_dir/mysql.sql.bz2"
		rm "$dest_dir/rsync.log"
	else
		dest_dir=$newdir/${server}
		rsync_par="--log-file=$dest_dir/rsync.log --link-dest=$olddir/${server}"

		mkdir $newdir/${server}
	fi

	if [ "${server}" == "localhost" ]; then
		if [ "${mysql_opt}" ]; then
			echo "Executing mysqldump ${mysql_opt}"
			mysqldump ${mysql_opt}|bzip2 -c >$dest_dir/mysql.sql.bz2
		fi
		rsync $rsync_opt $rsync_par ${files} $dest_dir/
		status_rsync=$?
	else
		if [ "${mysql_opt}" ]; then
			echo "Executing mysqldump ${mysql_opt} on ${server}"
			ssh -n ${server} "mysqldump ${mysql_opt}|bzip2 -c">$dest_dir/mysql.sql.bz2
		fi
		rsync $rsync_opt $rsync_par ${server}:"${files}" $dest_dir/
		status_rsync=$?
	fi

	if [ $status_rsync == 0 ]; then
		echo -ok- $server>>$log
	else
		echo FAIL $server $status_rsync>>$log
	fi

	IFS=","
done

if [ "$snapshot" == "1" ]; then
	btrfs subvolume snapshot $curdir $newdir
fi

cat $log
