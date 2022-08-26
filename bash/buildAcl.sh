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
DFT_ANSI_SSH_PRIV_KEY="/Users/yabinmeng/.ssh/id_rsa_ymtest"
DFT_ANSI_SSH_USER="automaton"


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

aclRawDefHomeDir="./permission_matrix"

validAclOpTypeArr=("grant" "revoke")
validAclOpTypeListStr="${validAclOpTypeArr[@]}"
debugMsg "validAclOpTypeListStr=${validAclOpTypeListStr}"

validResourceTypeArr=("topic" "namespace" "ns-subscription" "tp-subscription")
validResourceTypeListStr="${validResourceTypeArr[@]}"
debugMsg "validResourceTypeListStr=${validResourceTypeListStr}"

validAclActionArr=("produce" "consume" "sources" "sinks" "functions" "packages")
validAclActionListStr="${validAclActionArr[@]}"
debugMsg "validAclActionListStr=${validAclActionListStr}"

usage() {
   echo
   echo "Usage: buildAnsiHostInvFile.sh [-h]"
   echo "                                -clstrName <cluster_name>"
   echo "                                -aclDef <acl_definition_file>"
   echo "                               [-skipRoleJwt] <skip_role_jwt_generation>"
   echo "                               [-ansiPrivKey <ansi_private_key>"
   echo "                               [-ansiSshUser <ansi_ssh_user>"
   echo "       -h : Show usage info"
   echo "       -clstrName : Pulsar cluster name"
   echo "       -aclDef : Pulsar ACL definition file"
   echo "       [-skipRoleJwt] : Whether to skip JWT token generation for the specified roles"
   echo "       [-ansiPrivKey] : The private SSH key file used to connect to Ansible hosts"
   echo "       [-ansiSshUser] : The SSH user used to connect to Ansible hosts"
   echo
}

if [[ $# -eq 0 || $# -gt 10 ]]; then
   usage
   exit 10
fi

while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -clstrName) clstrName=$2; shift ;;
      -aclDef) aclDefFileName=$2; shift ;;
      -skipRoleJwt) skipRoleJwt=$(echo $2 | tr '[:upper:]' '[:lower:]'); shift ;;
      -ansiPrivKey) ansiPrivKey=$2; shift ;;
      -ansiSshUser) ansiSshUser=$2; shift ;;
      *) echo "[ERROR] Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

ANSI_HOSTINV_FILE="hosts_${clstrName}.ini"

aclDefExecLogHomeDir="${aclRawDefHomeDir}/${clstrName}/logs"
mkdir -p "${aclDefExecLogHomeDir}/acl_perm_exec_log"

aclDefFilePath="${aclRawDefHomeDir}/${clstrName}/${aclDefFileName}"

if [[ -z "${ansiPrivKey// }" ]]; then
    ansiPrivKey=${DFT_ANSI_SSH_PRIV_KEY}
fi

if [[ -z "${ansiSshUser// }" ]]; then
    ansiSshUser=${DFT_ANSI_SSH_USER}
fi

debugMsg "aclDefFilePath=${aclDefFilePath}"
debugMsg "ansiPrivKey=${ansiPrivKey}"
debugMsg "ansiSshUser=${ansiSshUser}"

# Check if the corrsponding Pulsar cluster definition file exists
if ! [[ -f "${aclDefFilePath}" ]]; then
    echo "[ERROR] Can't find the specified ACL raw definition file of the specific Pulsar cluster: ${aclDefFilePath}";
    exit 30
fi

re='(true|false)'
if [[ -z "${skipRoleJwt// }" ]]; then
    skipRoleJwt="false"
fi
if ! [[ ${skipRoleJwt} =~ $re ]]; then
    echo "[ERROR] Invalid value for the following input parameter of '-skipRoleJwt'. Value 'true' or 'false' is expected." 
    exit 40
fi


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

echo
stepCnt=0

stepCnt=$((stepCnt+1))
echo "${stepCnt}. Process the specified raw ACL definition file for validity check: ${aclDefFilePath} ..."

roleNameArr=()
uniqueRoleNameArr=()
aclOpArr=()
resourceTypeArr=()
resourceNameArr=()
aclActionListStrArr=()

while read LINE || [ -n "${LINE}" ]; do
    # Ignore comments
    case "${LINE}" in \#*) continue ;; esac
    IFS=',' read -r -a FIELDS <<< "${LINE#/}"

    roleName=${FIELDS[0]}
    aclOp=${FIELDS[1]}
    resourceType=${FIELDS[2]}
    resourceName=${FIELDS[3]}
    aclActionListStr=${FIELDS[4]}

    debugMsg "roleName=${roleName}"
    debugMsg "aclOp=$(echo ${aclOp} | tr '[:upper:]' '[:lower:]')"
    debugMsg "resourceType=$(echo ${resourceType} | tr '[:upper:]' '[:lower:]')"
    debugMsg "resourceName=${resourceName}"
    debugMsg "aclActionListStr=$(echo ${aclActionListStr} | tr '[:upper:]' '[:lower:]')"
    
    # General validity test
    if [[ -z "${roleName// }"||  -z "${aclOp// }" || -z "${resourceType// }" || -z "${resourceName// }" ]]; then
        echo "[ERROR] Invalid ACL defintion line: \"${LINE}\". All fields (except 'aclOption') must not be empty!" 
        exit 50
    elif ! [[ "${validAclOpTypeListStr}" =~ "${aclOp}" ]]; then 
        echo "[ERROR] Invalid ACL operation type '${aclOp}' on line \"${LINE}\". Valid types: ${validAclOpTypeListStr}" 
        exit 60
    elif ! [[ "${validResourceTypeListStr}" =~ "${resourceType}" ]]; then 
        echo "[ERROR] Invalid ACL resouce type '${resourceType}' on line \"${LINE}\". Valid types: ${validResourceTypeListStr}" 
        exit 70
    else
        IFS='+' read -r -a aclLineActionArr <<< "${aclActionListStr}"
        for aclAction in ${aclLineActionArr[@]} ; do
            if ! [[ "${validAclActionListStr}" =~ "${aclAction}" ]]; then 
                echo "[ERROR] Invalid ACL action type '${aclAction}' on line \"${LINE}\". Valid types: ${validAclActionListStr}" 
                exit 80
            fi
        done
    fi

    # Resource type specific validity check
    tp_re="^(persistent|non-persistent)://[[:alnum:]_-]+/[[:alnum:]_-]+/[[:alnum:]_-]+$"
    ns_re="^[[:alnum:]_-]+/[[:alnum:]_-]+$"
    ns_sb_re="^[[:alnum:]_-]+/[[:alnum:]_-]+:[[:alnum:]_-]+$"
    if [[ "${resourceType}" == "topic" ]]; then
        if ! [[ "${resourceName}" =~ ${tp_re} ]]; then
            echo "[ERROR] Invalid resource name pattern ('${resourceName}') for the specified resource type '${resourceType}' on line \"${LINE}\". Expecting name pattern: \"${tp_re}\"!" 
            exit 90
        fi
    elif [[ "${resourceType}" == "namespace" ]]; then
        if ! [[ "${resourceName}" =~ ${ns_re} ]]; then
            echo "[ERROR] Invalid resource name pattern ('${resourceName}') for the specified resource type '${resourceType}' on line \"${LINE}\". Expecting name pattern: \"${ns_re}\"!" 
            exit 100
        fi
    elif [[ "${resourceType}" == "ns-subscription" ]]; then
        if ! [[ "${resourceName}" =~ ${ns_sb_re} ]]; then
            echo "[ERROR] Invalid resource name pattern ('${resourceName}') for the specified resource type '${resourceType}' on line \"${LINE}\". Expecting name pattern: \"${ns_sb_re}\"!" 
            exit 110
        fi
    fi

    # aclActionListStr can be empty for 'subscription' resource 
    if [[ -z "${aclActionListStr// }" ]]; then
        aclActionListStr="n/a"
    fi

    roleNameArr+=("${roleName}")
    containsElementInArr "${roleName}" "${uniqueRoleNameArr[@]}"
    if [[ $? -eq 1 ]]; then
        uniqueRoleNameArr+=("${roleName}")
    fi

    aclOpArr+=("${aclOp}")
    resourceTypeArr+=("${resourceType}")
    aclActionListStrArr+=("${aclActionListStr}")
    resourceNameArr+=("${resourceName}")

done < ${aclDefFilePath}

roleNameList="${roleNameArr[@]}"
uniqueRoleNameList="${uniqueRoleNameArr[@]}"
aclOpList="${aclOpArr[@]}"
resourceTypeList="${resourceTypeArr[@]}"
aclActionListStrList="${aclActionListStrArr[@]}"
debugMsg "roleNameList=${roleNameList}"
debugMsg "uniqueRoleNameList=${uniqueRoleNameList}"
debugMsg "aclOpList=${aclOpList}"
debugMsg "resourceTypeList=${resourceTypeList}"
debugMsg "aclActionListStrArr=${aclActionListStrList}"
echo "   done!"

if [[ "${skipRoleJwt}" == "false" ]]; then
    echo
    stepCnt=$((stepCnt+1))
    
    ansiPlaybookName="01.create_secFiles.yaml"
    ANSI_HOSTINV_FILE="hosts_${clstrName}.ini"
    ansiTcExecLog="${aclDefExecLogHomeDir}/${aclDefFileName}-create_secFiles.yaml.log"
    
    echo "${stepCnt}. Call Ansible script to create JWT tokens for all roles specified in the ACL raw definition file"
    echo "   execution log file: ${ansiTcExecLog}"
    ansible-playbook -i ${ANSI_HOSTINV_FILE} ${ansiPlaybookName} \
        --extra-vars="cleanLocalSecStaging=false user_roles_list=${uniqueRoleNameList// /,} jwtTokenOnly=true brokerOnly=true" \
        --private-key=${ansiPrivKey} \
        -u ${ansiSshUser} -v > ${ansiTcExecLog} 2>&1

    if [[ $? -ne 0 ]]; then
        echo "   [ERROR] Failed to create specifie JWT tokens for the specified roles!" 
        exit 120
    else
        echo "   done!"
    fi
    echo
fi

echo
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Generate pulsar-amdin command template file to grant/revoke permissions according to the ACL definition."

pulsarCliAclExecTemplFile="${aclRawDefHomeDir}/${clstrName}/${aclDefFileName}_pulsarCliCmdTmpl"
echo "#! /bin/bsh" > ${pulsarCliAclExecTemplFile}
echo >> ${pulsarCliAclExecTemplFile}
echo "aclIndex=0" >> ${pulsarCliAclExecTemplFile}
echo >> ${pulsarCliAclExecTemplFile}

for index in "${!roleNameArr[@]}"; do
    roleName=${roleNameArr[$index]}
    aclOp=${aclOpArr[$index]}
    resourceType=${resourceTypeArr[$index]}
    resourceName=${resourceNameArr[$index]}

    # convert to the format recogonized by pulsar-admin command
    aclActionListStr=$(echo ${aclActionListStrArr[$index]} | tr '+' ',' )

    if [[ "${resourceType}" == "namespace" ]]; then
        adminCmd="namespaces"
        adminSubCmd="${aclOp}-permission"
    elif [[ "${resourceType}" == "topic" ]]; then
        adminCmd="topics"
        adminSubCmd="${aclOp}-permission"
    elif [[ "${resourceType}" == "ns-subscription" ]]; then
        adminCmd="namespaces"
        adminSubCmd="${aclOp}-subscription-permission"
    #
    ## future work: topic subscription
    #
    # elif [[ "${resourceType}" == "ns-subscription" ]]; then
    #     adminCmd="namespaces"
    #     adminSubCmd="${aclOp}-subscription-permission"
    fi

    pulsarAdminCmdStrToExec="<PULSAR_ADMIN_CMD> ${adminCmd} ${adminSubCmd}"

    if [[ "${resourceType}" == "ns-subscription" ]]; then
        # for "ns-subscription", the resource name is in format "<tenant>/<namespace>:<subscription>"
        IFS=':' read -r -a nsSubArr <<< "${resourceName}"
        pulsarAdminCmdStrToExec="${pulsarAdminCmdStrToExec} ${nsSubArr[0]} --subscription ${nsSubArr[1]} --roles ${roleName}"
    #
    ## future work: topic subscription
    #
    # elif [[ "${resourceType}" == "ns-subscription" ]]; then
    #     pulsarAdminCmdStrToExec="TBD ..."
    else
        pulsarAdminCmdStrToExec="${pulsarAdminCmdStrToExec} ${resourceName} --role ${roleName}"
        if [[ "${aclOp}" == "grant" ]]; then
            pulsarAdminCmdStrToExec="${pulsarAdminCmdStrToExec} --actions ${aclActionListStr}"
        fi
    fi

    echo 'aclIndex=$((aclIndex+1))' >> ${pulsarCliAclExecTemplFile}
    echo "${pulsarAdminCmdStrToExec}" >> ${pulsarCliAclExecTemplFile}
    echo 'if [[ $? -ne 0 ]]; then' >> ${pulsarCliAclExecTemplFile}
    echo '    exit ${aclIndex}' >> ${pulsarCliAclExecTemplFile}
    echo 'fi' >> ${pulsarCliAclExecTemplFile}
    echo >> ${pulsarCliAclExecTemplFile}  
done
echo 'exit 0' >> ${pulsarCliAclExecTemplFile}
echo "   done!"

echo
stepCnt=$((stepCnt+1))

ansiPlaybookName="exec_AclPermControl.yaml"
ansiTcExecLog="${aclDefExecLogHomeDir}/${aclDefFileName}-exec_AclPermControl.yaml.log"

echo "${stepCnt}. Call Ansible script to execute Pulsar ACL permission management commands"
echo "   execution log file: ${ansiTcExecLog}"
ansible-playbook -i ${ANSI_HOSTINV_FILE} ${ansiPlaybookName} \
    --extra-vars="aclDefRawName=${aclDefFileName}" \
    --private-key=${ansiPrivKey} \
    -u ${ansiSshUser} -v > ${ansiTcExecLog} 2>&1

if [[ $? -ne 0 ]]; then
    echo "   [ERROR] Not all Pulsar ACL permission management commands are executed successfully! Please check the remote execute log!" 
    exit 120
else
    echo "   done!"
fi
echo