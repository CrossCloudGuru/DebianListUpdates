#!/usr/bin/env bash
# Version: 20210128-1603
# Author: Marco Tijbout
#
# This script is used to generate a list of security updates that are available
# for installation on the specified hosts in the input file.
#
# Syntax:
# ./listSecurityUpdates.sh <input_file_with_list_of_servers_to_check>

# Let's begin ...
echo -e "\n\nStart processing $0"

# Current date and time of script execution
DATETIME=`date +%Y%m%d_%H%M%S`

fnSucces() {
    if [ $EXITCODE -eq 0 ]; then
        echo -e "  - Succesful.\n"
    else
        echo -e "  - Failed!"
        # Consider exiting.
        echo -e "  - Exitcode: $EXITCODE"
        # exit $EXITCODE
    fi
}

# Check if an environment file is supplied on the command line.
if [ $# -eq 0 ]
then
    echo -e "No arguments supplied.\nPlease provide name of env file to process ..."
    exit 1
fi

# Source the variables
ENV_FILE=$1
. ./"${ENV_FILE}"
echo -e "\nEnvironment file loaded: ${ENV_FILE}"

# Specify the Sysadmin Admin credential details. While executing a password 
# for the private key may be asked.
USER=remoteUserName
SSH_ID="~/.ssh/id_to_use"
ADMIN="-i ${SSH_ID} ${USER}"
echo -e "\n- Load SSH Agent ..."
eval $(ssh-agent -s)

echo -e "\n- Load SSH Key ..."
ssh-add "${SSH_ID}"

fnCombineLogs() {
    echo -e '\n# ---------------------------------------------------------------------------- #' >> security-updates-${DATETIME}-all.txt
    # REMOTE_NAME=$(dig +short -x $i) >> security-updates-${DATETIME}-all.txt
    echo -e "Hostname       : ${REMOTE_NAME}" >> security-updates-${DATETIME}-all.txt
    echo -e "IP Address     : ${i}" >> security-updates-${DATETIME}-all.txt
    echo -e "Reboot required: ${REBOOT_REQ}" >> security-updates-${DATETIME}-all.txt
    echo -e "\nSecurity updates available:" >> security-updates-${DATETIME}-all.txt
    cat ./output/security-updates-${DATETIME}-${i}.txt >> security-updates-${DATETIME}-all.txt
    echo -e "\n"
}

# For each host in the array the below actions are performed.
for i in "${HOSTS[@]}"
do
    echo -e "\nNow connecting to: ${i}"

    echo -e "- Quietly updating the apt repositories ..."
    ssh ${ADMIN}@$i sudo apt-get -qq update
    EXITCODE=$?; fnSucces $EXITCODE

    echo -e "- Generate list of available security updates ..."
    ssh ${ADMIN}@$i "sudo apt list --upgradable | grep security > /home/${USER}/security-updates-${DATETIME}-${i}.txt"
    # ssh ${ADMIN}@$i "sudo apt list --upgradable > /home/${USER}/security-updates-${DATETIME}-${i}.txt"
    EXITCODE=$?; fnSucces $EXITCODE

    # echo -e "\n- See what is in the home folder:"
    # ssh ${ADMIN}@$i ls -l /home/${USER}/

    echo -e "- Copy over the file to local ..."
    scp -C -i ${SSH_ID} ${USER}@${i}:/home/${USER}/security-updates-${DATETIME}-${i}.txt ./output
    EXITCODE=$?; fnSucces $EXITCODE

    echo -e "- Remove the file from host ..."
    #ssh ${ADMIN}@$i rm /home/${USER}/security-updates-${DATETIME}-${i}.txt
    ssh ${ADMIN}@$i rm /home/${USER}/security-updates-*.txt
    EXITCODE=$?; fnSucces $EXITCODE

    echo -e "- Check if reboot is required ..."
    if ssh ${ADMIN}@$i stat /var/run/reboot-required \> /dev/null 2\>\&1
    then
        echo -e "  - Reboot is pending!"
        echo -e "$i" >> reboot-required-${DATETIME}.txt
        REBOOT_REQ=True
    else
        echo -e "  - No reboot pending ..."
        REBOOT_REQ=False
    fi

    echo -e "\n- Get the FQDN of the host ..."
    REMOTE_NAME=$(ssh ${ADMIN}@$i dig +short -x $i)

    # combine logs
    fnCombineLogs ${i} ${REBOOT_REQ} ${REMOTE_NAME}
done

# The End ...
echo -e "\nFinished processing $0\n\n"
