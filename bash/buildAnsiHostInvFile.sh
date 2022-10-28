###
# Copyright DataStax, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###


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

DEBUG=false

bashVerCmdOut=$(bash --version)
re='[0-9].[0-9].[0-9]'
bashVersion=$(echo ${bashVerCmdOut} | grep -o "version ${re}" | grep -o "${re}")
bashVerMajor=$(echo ${bashVersion} | awk -F'.' '{print $1}' )

if [[ ${bashVerMajor} -lt 4 ]]; then
    echo "[ERROR] Unspported bash version (${bashVersion}). Must be version 4.x and above!";
    exit 1
fi

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

validPulsarSrvHostTypeArr=("zookeeper" "bookkeeper" "broker" "autorecovery" "functions_worker")
validPulsarSrvHostTypeListStr="${validPulsarSrvHostTypeArr[@]}"
debugMsg "validPulsarClntHostTypeListStr=${validPulsarClntHostTypeListStr}"

validPulsarClntHostTypeArr=(${validPulsarSrvHostTypeArr[@]} "standAloneClient")
validPulsarClntHostTypeListStr="${validPulsarClntHostTypeArr[@]}"
debugMsg "validPulsarClntHostTypeListStr=${validPulsarClntHostTypeListStr}"

validHostTypeArr+=( ${validPulsarClntHostTypeArr[@]} "adminConsole" "heartBeat" )
validHostTypeListStr="${validHostTypeArr[@]}"
debugMsg "validHostTypeListStr=${validHostTypeListStr}"

###
# The valid status can be either
# - (empty value/not set): node already in the cluster or to be added
# - 'remove': remove node from the cluster
validDeployStatusArr=("remove")
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

# Map of server type to an array of internal IPs/HostNames
declare -A internalHostIpMap
declare -A externalHostIpMap
declare -A regionMap
declare -A azMap
declare -A brokerCPMap
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
        
        hostType=${FIELDS[2]}        
        region=${FIELDS[3]}
        aZone=${FIELDS[4]}
        brokerCP=${FIELDS[5]}
        deployStatus=${FIELDS[6]}

        debugMsg "internalIp=${internalIp}"
        debugMsg "externalIp=${externalIp}"
        debugMsg "hostType=${hostType}"
        debugMsg "region=${region}"
        debugMsg "aZone=${aZone}"
        debugMsg "brokerCP=${brokerCP}"
        debugMsg "deployStatus=${deployStatus}"
        
        if [[ -z "${internalIp// }"||  -z "${hostType// }" || -z "${region// }" || -z "${aZone// }" ]]; then
            echo "[ERROR] Invalid server host defintion line: \"${LINE}\". Mandatory fields must not be empty!" 
            exit 50
        fi

        if ! [[ "${validHostTypeArr[*]}" =~ "${hostType// }" ]]; then
            echo "[ERROR] Invalid server host type at line \"${LINE}\"." 
            echo "        must be one of the following values: \"${validPulsarSrvHostTypeListStr}\""
            exit 60
        fi

        if [[ "${hostType}" =~ "broker" ]]; then
            if ! [[ -z "${brokerCP// }" || "${brokerCP// }" == "yes" || "${brokerCP// }" == "no" ]]; then
                echo "[ERROR] Broker contact point filed must be 'yes' or 'no' (line:  \"${LINE}\")." 
                exit 70
            elif [[ -z "${brokerCP// }" ]]; then
                brokerCP="no"
            fi
        fi

        if ! [[ -z "${deployStatus// }" || "${validDeployStatusArr[*]}" =~ "${deployStatus}" ]]; then
            echo "[ERROR] Invalid server deployment status (line: \"${LINE}\"). Must be empty or one of the following: \""${validDeployStatusArr[*]}"\"" 
            exit 80
        fi

        internalHostIpMap[${hostType}]+="${internalIp} "
        externalHostIpMap[${hostType}]+="${externalIp} "
        regionMap[${hostType}]+="${region} "
        azMap[${hostType}]+="${aZone} "
        if [[ "${hostType}" == "broker" ]]; then
            brokerCPMap[${hostType}]+="${brokerCP} "
        else
            brokerCPMap[${hostType}]+=" "
        fi
        deployStatusMap[${hostType}]+="${deployStatus} "
    fi

done < ${clstTopFile}

##
# example to print out associative array keys and values
# for key in "${!deployStatusMap[@]}"; do echo $key; done
# for val in "${internalHostIpMap[@]}"; do echo $val; done

repeatSpace() {
    head -c $1 < /dev/zero | tr '\0' ' '
}

# Two parameter: 
# - 1st parameter is the message to print for execution status purpose
# - 2nd parameter is the number of the leading spaces
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
for pulsarSrv in "${validPulsarSrvHostTypeArr[@]}"; do
   outputMsg "${pulsarSrv}"
done
outputMsg ""
outputMsg "[pulsarServer:vars]"
outputMsg "srv_component_list=[\"$(echo ${validPulsarSrvHostTypeListStr} | sed -e 's/\s\+/\", \"/g')\"]"
outputMsg ""

for hostType in "${validHostTypeArr[@]}"; do
    internalIpSrvTypeList="${internalHostIpMap[${hostType}]}"
    externalIpSrvTypeList="${externalHostIpMap[${hostType}]}"
    regionSrvTypeList="${regionMap[${hostType}]}"
    azSrvTypeList="${azMap[${hostType}]}"
    brokerCPSrvTypeList="${brokerCPMap[${hostType}]}"
    deployStatusSrvTypeList="${deployStatusMap[${hostType}]}"

    IFS=' ' read -r -a internalIpSrvTypeArr <<< "${internalIpSrvTypeList}"
    IFS=' ' read -r -a externalIpSrvTypeArr <<< "${externalIpSrvTypeList}"
    IFS=' ' read -r -a regionSrvTypeArr <<< "${regionSrvTypeList}"
    IFS=' ' read -r -a azSrvTypeArr <<< "${azSrvTypeList}"
    IFS=' ' read -r -a brokerCPSrvTypeArr <<< "${brokerCPSrvTypeList}"
    IFS=' ' read -r -a deployStatusSrvTypeArr <<< "${deployStatusSrvTypeList}"

    if [[ "${validPulsarClntHostTypeListStr}" =~ "${hostType}" ]]; then
        outputMsg "[${hostType}:vars]"
        outputMsg "srv_component=\"$(echo ${hostType})\""

        if [[ "${validPulsarSrvHostTypeListStr}" =~ "${hostType}" ]]; then
            if [[ "${hostType}" == "bookkeeper" ]]; then
                srv_component_internal="bookie"
            elif [[ "${hostType}" == "functions_worker" ]]; then
                srv_component_internal="functions-worker"
            else
                srv_component_internal="${hostType}"
            fi
            outputMsg "srv_component_internal=\"$(echo ${srv_component_internal})\""
        fi
    fi
    outputMsg "[${hostType}]"

    for index in "${!internalIpSrvTypeArr[@]}"; do
        hostInvLine="${externalIpSrvTypeArr[$index]} private_ip=${internalIpSrvTypeArr[$index]}"
        hostInvLine="${hostInvLine} region=${regionSrvTypeArr[$index]}"
        hostInvLine="${hostInvLine} az=${azSrvTypeArr[$index]}"
        hostInvLine="${hostInvLine} rack_name=${regionSrvTypeArr[$index]}-${azSrvTypeArr[$index]}"

        if [[ "${hostType}" == "broker" ]]; then
            hostInvLine="${hostInvLine} contact_point=${brokerCPSrvTypeArr[$index]}"
        fi

        if [[ "${validPulsarClntHostTypeListStr}" =~ "${hostType}" ]]; then
            hostInvLine="${hostInvLine} deploy_status=${deployStatusSrvTypeArr[$index]}"
        fi 

        outputMsg "$hostInvLine"
    done

    outputMsg ""
done