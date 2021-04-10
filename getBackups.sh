#!/usr/bin/env bash


##
# @param $1 message (string)
# @return null
##
postNotification() {
    terminal-notifier \
        -group "com.finnlesueur.backups" \
        -title "Server Backup" \
        -message "$1" \
        -appIcon "https://seeklogo.com/images/L/linode-logo-0B22204438-seeklogo.com.png" > /dev/null 2>&1
}


##
# @param $1 exit_code (0-255)
# @param $2 message (string)
# @return null
##
logCommandCompletionCode() {
    if [ "$1" -eq 0 ]
    then
        msg="✅ $2"
        echo "$msg"
        postNotification "$msg"
    else
        msg="❌ $2"
        echo "$msg"
        postNotification "$msg"
        exit 1
    fi
}


##
# The brains.
# @param null
# @return null
##
main() {

    ##
    # Load some variables:
    #
    # webServerIP
    # webServerUser
    # emailServer
    # emailServerUser
    ##
    source backup.config

    currentDate=$(date +%Y-%m-%d)
    postNotification "Started"
    dt=$(date '+%d/%m/%Y %H:%M:%S');
    echo "[$dt]: Backup Started"

    ##
    # Start by syncing some webserver
    # folders to the local machine.
    ##
    if [[ ! -d "server" ]]; then
            mkdir "server"
    fi

    server="${webServerUser}@${webServerIP}"

    cd "server" || exit

    folders=("/srv" "/home" "/root" "/opt" "/etc/apache2" "/etc/php")
    for folder in "${folders[@]}"
    do
        rsync --archive --compress --delete "$server:$folder" ./
        logCommandCompletionCode $? "synced $folder"
    done

    ##
    # Create a dump of the mySQL database
    # and then sync it to the local machine.
    ##
    ssh ${server} "mysqldump --all-databases > '/my.sql' && exit"
    logCommandCompletionCode $? "mySQL database dump"

    rsync --archive ${server}:/my.sql ./
    logCommandCompletionCode $? "synced my.sql"

    ssh ${server} "rm /my.sql && exit"
    logCommandCompletionCode $? "my.sql removed from server"
    cd ../ || exit

    ##
    # Make a .tar.gz of the webserver contents,
    # and then remove old tar.gz's from the
    # local machine.
    ##
    tar --create --gzip --file="$currentDate.tar.gz" "server"
    logCommandCompletionCode $? "$currentDate.tar.gz created"
    mv "$currentDate.tar.gz" Webserver/

    cd Webserver/ || exit
    find . -name "*.tar.gz" | awk 'NR>5' | xargs rm
    logCommandCompletionCode $? "old backups deleted"
    
    ##
    # Backup the mailinabox archives
    # from the email virtual machine.
    ##
    rsync --archive --perms --delete "${emailServerUser}@${emailServerIP}:/home/user-data/backup/encrypted/" ~/Backups/Emails/
    logCommandCompletionCode $? "emails synced"
}

TIMEFORMAT='%0R'
t="$( { time main >> backup.log 2>&1; } )"
dt=$(date '+%d/%m/%Y %H:%M:%S');
echo "[$dt]: Backup Finished (${t}s)" >> backup.log 2>&1
