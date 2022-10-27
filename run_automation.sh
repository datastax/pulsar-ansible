#! /bin/bash

source $(pwd)/setenv_automation.sh
echo

usage() {
   echo
   echo "Usage: run_automation.sh [-h][<playbook> [--extra-vars '\"...\"']]"
   echo
   echo "       -h : show usage info"
   echo '       $1 : ansible playbook yaml name'
   echo '       $2, ... : other variables needed by the playbook'
   echo
}

if [[ $# -eq 0 || "$@" =~ .*"-h".* ]]; then
    usage
    exit 0;
fi

outputToLog=0
if [[ "$@" =~ .*"-l".* ]]; then
    outputToLog=1
fi

# Check if the required environment variables are set
if [[ -z "${ANSI_SSH_PRIV_KEY// }" || -z "${ANSI_SSH_USER// }" || -z "${ANSI_DEBUG_LVL// }" || -z "${CLUSTER_NAME// }" ]]; then
    echo "Required environment variables are not set in 'setenv_automation.sh' file!"
    exit 10
fi

# Check if the required host inventory file exists
ANSI_HOSTINV_FILE="$(pwd)/hosts_${CLUSTER_NAME}.ini"
if ! [[ -f "${ANSI_HOSTINV_FILE}" ]]; then
    echo "The corresponding host inventory file for cluster \"${CLUSTER_NAME}\". Please run 'bash/buildAnsiHostInvFile.sh' file to generate it!"
    exit 20
fi

curTime=$(date "+%F %X")
IFS=' ' read -r -a timeFields <<< "${curTime}"

execLogDir="automation_exec_logs/${timeFields[0]}"
if ! [[ -d ${execLogDir} ]]; then
    mkdir -p ${execLogDir}
fi

execLogFile="${1}_${timeFields[1]}.log"

echo "============================================="
echo "= Start exeucting ansible playbook: \"${1}\"..."
echo "============================================="
echo

inputParamListStr=$(echo $@ | sed -e 's/-l\s*//g')

ansiCmd="ansible-playbook ${inputParamListStr} -i ${ANSI_HOSTINV_FILE} --private-key ${ANSI_SSH_PRIV_KEY} -u ${ANSI_SSH_USER} ${ANSI_DEBUG_LVL}"
if [[ ${outputToLog} -eq 1 ]]; then
    ansiCmd="${ansiCmd} | tee -a ${execLogDir}/${execLogFile}"
fi

# echo "${ansiCmd}"
eval ${ansiCmd}

echo
echo "============================================="
echo "= Exection finished with return code: $?"
if [[ ${outputToLog} -eq 1 ]]; then
    echo "=   log file : ./${execLogDir}/${execLogFile}"
fi
echo "============================================="
echo