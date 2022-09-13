#! /usr/local/bin/bash

###
# NOTE 1: the default MacOS /bin/bash version is 3.x and doesn't have the feature of 
#         associative arrary. Homebrew installed bash is under "/usr/local/bin/bash"
#
# Change to default "/bin/bash" if your system has the right version (4.x and above)
#

# This script is used for generating the Ansible host inventory file from
#   the cluster topology raw definition file
# 
#   this script only works for bash 4 and above
#   * by default, MacOs bash version is 3.x (/bin/bash)
#   * use custom-installed bash using homebrew (/usar/local/bin/bash) at version 5.x
#

bashVerCmdOut=$(bash --version)
re='[0-9].[0-9].[0-9]'
bashVersion=$(echo ${bashVerCmdOut} | grep -o "version ${re}" | grep -o "${re}")
bashVerMajor=$(echo ${bashVersion} | awk -F'.' '{print $1}' )

if [[ ${bashVerMajor} -lt 4 ]]; then
    echo "[ERROR] Unspported bash version (${bashVersion}). Must be version 4.x and above!";
    exit 1
fi

DEBUG=false

# only 1 parameter: the message to print for debug purpose
debugMsg() {
    if [[ "${DEBUG}" == "true" ]]; then
        if [[ $# -eq 0 ]]; then
            echo
        else
            echo "[Debug] $1"
        fi
    fi
}

clstrToplogyRawDefHomeDir="./cluster_topology"

validHostTypeArr=("zookeeper" "bookkeeper" "broker" "functions_worker" "standAloneClient" "adminConsole" "heartBeat")
validHostTypeListStr="${validHostTypeArr[@]}"
debugMsg "validHostTypeListStr=${validHostTypeListStr}"

validPulsarHostTypeArr=("zookeeper" "bookkeeper" "broker" "functions_worker" "standAloneClient")
validPulsarHostTypeListStr="${validPulsarHostTypeArr[@]}"
debugMsg "validPulsarHostTypeListStr=${validPulsarHostTypeListStr}"

validDeployStatusArr=("current" "add" "remove")
validDeployStatusListStr="${validDeployStatusArr[@]}"
debugMsg "validDeployStatusListStr=${validDeployStatusListStr}"

usage() {
   echo
   echo "Usage: buildAnsiHostInvFile.sh [-h]"
   echo "                                -clstrName <cluster_name>"
   echo "                                -hostDns <whehter_using_dnsname>"
   echo "       -h : Show usage info"
   echo "       -clstrName : Pulsar cluster name"
   echo "       -hostDns   : Whehter using host DNS name (true) or host IP (faslse)"
   echo
}

if [[ $# -eq 0 || $# -gt 4 ]]; then
   usage
   exit 10
fi

while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -clstrName) clstrName=$2; shift ;;
      -hostDns) hostDns=$2; shift ;;
      *) echo "[ERROR] Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

clstTopFile="${clstrToplogyRawDefHomeDir}/${clstrName}/clusterDefRaw"
lastClstTopFile="${clstrToplogyRawDefHomeDir}/${clstrName}/clusterDefRaw_last"

debugMsg "clstTopFile=${clstTopFile}"
debugMsg "lastClstTopFile=${lastClstTopFile}"
debugMsg "hostDns=${hostDns}"

# Check if the corrsponding Pulsar cluster definition file exists
if ! [[ -f "${clstTopFile}" ]]; then
    echo "[ERROR] The spefified Pulsar cluster doesn't have the corresponding topology definition file: ${clstTopFile}";
    exit 30
fi

re='(true|false)'
if ! [[ ${hostDns} =~ $re ]]; then
  echo "[ERROR] Invalid value for the input parameter '-hostDns'. Boolean value (true or false) is expected." 
  exit 40
fi

tgtAnsiHostInvFileName="hosts_${clstrName}.ini"
echo > ${tgtAnsiHostInvFileName}

##
# Check if an element is contained in an arrary
# - 1st parameter: the element to match
# - 2nd parameter: the array 
containsElementInArr () {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

# Map of server type to an array of internal IPs/HostNames
declare -A internalHostIpMap
declare -A externalHostIpMap
declare -A regionAzMap
declare -A deployStatusMap

while read LINE || [ -n "${LINE}" ]; do
    # Ignore comments
    case "${LINE}" in \#*) continue ;; esac
    IFS=',' read -r -a FIELDS <<< "${LINE#/}"

    if [[ -n "${LINE// }" ]]; then
        internalIp=${FIELDS[0]}
        externalIp=${FIELDS[1]}
        if [[ -z "${externalIp// }" ]]; then
            externalIp=${internalIp}
        fi 
        providedHostTypeList=${FIELDS[2]}
        region=${FIELDS[3]}
        aZone=${FIELDS[4]}
        deployStatus=${FIELDS[5]}

        debugMsg "internalIp=${internalIp}"
        debugMsg "externalIp=${externalIp}"
        debugMsg "hostTypeList=${providedHostTypeList}"
        debugMsg "region=${region}"
        debugMsg "aZone=${aZone}"
        debugMsg "deployStatus=${deployStatus}"
        
        if [[ -z "${internalIp// }"||  -z "${providedHostTypeList// }" || 
            -z "${region// }" || -z "${aZone// }" || -z "${deployStatus// }" ]]; then
            echo "[ERROR] Invalid server host defintion line: \"${LINE}\". All fields (except 2nd) must not be empty!" 
            exit 50
        fi

        containsElementInArr "${deployStatus}" "${validDeployStatusArr[@]}"
        if [[ $? -eq 1 ]]; then
            echo "[ERROR] Invalid server deployment status in line: \"${LINE}\"." 
            exit 60
        fi

        for hostType in $(echo ${providedHostTypeList} | sed "s/+/ /g"); do        
            containsElementInArr "${hostType}" "${validHostTypeArr[@]}"
            if [[ $? -eq 1 ]]; then
                echo "[ERROR] Invalid host machine type in line: \"${LINE}\"." 
                exit 70
            fi

            internalHostIpMap[${hostType}]+="${internalIp} "
            externalHostIpMap[${hostType}]+="${externalIp} "
            regionMap[${hostType}]+="${region} "
            azMap[${hostType}]+="${aZone} "
            deployStatusMap[${hostType}]+="${deployStatus} "
        done
    fi

done < ${clstTopFile}

##
# example to print out associative array keys and values
# for key in "${!deployStatusMap[@]}"; do echo $key; done
# for val in "${internalHostIpMap[@]}"; do echo $val; done

repeatSpace() {
    head -c $1 < /dev/zero | tr '\0' ' '
}

# Three parameter: 
# - 1st parameter is the message to print for execution status purpose
# - 2nd parameter is the number of the leading spaces
# - 3nd parameter is whether to append the message to the main log file
outputMsg() {
    if [[ $# -eq 0 || $# -gt 2 ]]; then
        echo "[Error] Incorrect usage of outputMsg()."
    else
        leadingSpaceStr=""
        if [[ $# -eq 2 && $2 -gt 0 ]]; then
            leadingSpaceStr=$(repeatSpace $2)            
        fi
        echo "$leadingSpaceStr$1" >> ${tgtAnsiHostInvFileName}
    fi
}


outputMsg "[all:vars]"
outputMsg "cluster_name=${clstrName}"
outputMsg "use_dns_name=\"${hostDns}\""
outputMsg ""
outputMsg "[LSCluster:children]"
outputMsg "pulsarServer"
outputMsg "adminConsole"
outputMsg "heartBeat"
outputMsg ""
outputMsg "[pulsarClient:children]"
outputMsg "pulsarServer"
outputMsg "standAloneClient"
outputMsg ""
outputMsg "[pulsarServer:children]"
outputMsg "zookeeper"
outputMsg "bookkeeper"
outputMsg "broker"
outputMsg "functions_worker"
outputMsg ""

for hostType in "${validHostTypeArr[@]}"; do
    internalIpSrvTypeList="${internalHostIpMap[${hostType}]}"
    externalIpSrvTypeList="${externalHostIpMap[${hostType}]}"
    regionSrvTypeList="${regionMap[${hostType}]}"
    azSrvTypeList="${azMap[${hostType}]}"
    deployStatusSrvTypeList="${deployStatusMap[${hostType}]}"

    IFS=' ' read -r -a internalIpSrvTypeArr <<< "${internalIpSrvTypeList}"
    IFS=' ' read -r -a externalIpSrvTypeArr <<< "${externalIpSrvTypeList}"
    IFS=' ' read -r -a regionSrvTypeArr <<< "${regionSrvTypeList}"
    IFS=' ' read -r -a azSrvTypeArr <<< "${azSrvTypeList}"
    IFS=' ' read -r -a deployStatusSrvTypeArr <<< "${deployStatusSrvTypeList}"

    isScaling="false"
    if [[ "${deployStatusSrvTypeList}" =~ "add" ]]; then
        isScaling="true"
    fi

    if [[ "${validPulsarHostTypeListStr}" =~ "${hostType}" ]]; then
        outputMsg "[${hostType}:vars]"
        outputMsg "isScaling=\"${isScaling}\""
    fi
    outputMsg "[${hostType}]"

    for index in "${!internalIpSrvTypeArr[@]}"; do
        if [[ "${validPulsarHostTypeListStr}" =~ "${hostType}" ]]; then
            hostInvLine="${externalIpSrvTypeArr[$index]} private_ip=${internalIpSrvTypeArr[$index]} deploy_status=${deployStatusSrvTypeArr[$index]}"
        else
            hostInvLine="${externalIpSrvTypeArr[$index]} private_ip=${internalIpSrvTypeArr[$index]}"
        fi 

        if [[ "${hostType}" == "bookkeeper" ]]; then
            hostInvLine="${hostInvLine} rack_name=${regionSrvTypeArr[$index]}-${azSrvTypeArr[$index]}"
        fi
        outputMsg "$hostInvLine"
    done

    outputMsg ""
done