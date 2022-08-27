#! /bin/bash


DEBUG=false


#
# NOTE: this script is used for setting up geo-replication for 2 Pulsar clusters with security 
#       features enabled: JWT token authentication and TLS encryption. 
#
#       Before running this script, the following conditions must be met
#       1) 2 Pulsar clusters with security eabled must be deployed using "pulsar-ansible" playbooks
#       2) The security files (JWT token and TLS certificate files) must be available locally on the
#          Ansile controller machine (e.g. don't be deleted explicitly)
#
#


usage() {
   echo
   echo "Usage: 99.setup_georep_2region.sh [-h]"
   echo "                                  -ansiHostInvent1 <host_inventory_file1>"
   echo "                                  -ansiPrivKey1 <ansi_private_key1>"
   echo "                                  -ansiSshUser1 <ansi_ssh_user1>"
   echo "                                  -ansiHostInvent2 <host_inventory_file2>"
   echo "                                  -ansiPrivKey2 <ansi_private_key2>"
   echo "                                  -ansiSshUser2 <ansi_ssh_user2>"
   echo "                                  [-skipSrvFileFetch <skip_clntconf_fetch>]"
   echo "                                  [-skipClstrSetup <skip_cluster_setup>]"
   echo "                                  [-forceClstrUpdate <force_cluster_update>]"
   echo "                                  -tntNsList <tenant_namespace_list>"
   echo "                                  [-forceTntNsUpdate <force_tntns_update>]"
   echo "       -h   : Show usage info"
   echo "       -ansiHostInvent1    : Ansible host inventory file for Pulsar cluster 1"
   echo "       -ansiPrivKey1       : SSH private key to connect to Pulsar cluster 1"
   echo "       -ansiSshUser1       : SSH user to connect to Pulsar cluster 1"
   echo "       -ansiHostInvent2    : Ansible host inventory file for Pulsar cluster 2"
   echo "       -ansiPrivKey2       : SSH private key to connect to Pulsar cluster 2"
   echo "       -ansiSshUser2       : SSH user to connect to Pulsar cluster 2"
   echo "       [-skipSrvFileFetch]: Whether to skip fetching Pulsar cluster files from the remote host (default: false)!"
   echo "       [-skipClstrSetup]   : Whether to skip Pulsar cluster setup (default: false)!"
   echo "       [-forceClstrUpdate] : Whether to force updating existing cluster definition (default: false)!"
   echo "       -tntNsList          : Comma separated tenant and namespace list (e.g. tnt1/ns1,tnt2/ns2,...)"
   echo "       [-forceTntNsUpdate] : Whether to force updating existing tenant and namespace definition (default: false)!"
   echo
}

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

if [[ $# -eq 0 || $# -gt 22 ]]; then
   usage
   exit 10
fi

skipSrvFileFetch=false
skipClstrSetup=false
forceClstrUpdate=false
forceTntNsUpdate=false
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -ansiHostInvent1) ansiHostInvent1=$2; shift ;;
      -ansiPrivKey1) ansiPrivKey1=$2; shift ;;
      -ansiSshUser1) ansiSshUser1=$2; shift ;;
      -ansiHostInvent2) ansiHostInvent2=$2; shift ;;
      -ansiPrivKey2) ansiPrivKey2=$2; shift ;;
      -ansiSshUser2) ansiSshUser2=$2; shift ;;
      -skipSrvFileFetch) skipSrvFileFetch=$(echo $2 | tr '[:upper:]' '[:lower:]'); shift ;;
      -skipClstrSetup) skipClstrSetup=$(echo $2 | tr '[:upper:]' '[:lower:]'); shift ;;
      -forceClstrUpdate) forceClstrUpdate=$(echo $2 | tr '[:upper:]' '[:lower:]'); shift ;;
      -tntNsList) tntNsList=$2; shift ;;
      -forceTntNsUpdate) forceTntNsUpdate=$(echo $2 | tr '[:upper:]' '[:lower:]'); shift ;;
      *) echo "[ERROR] Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

debugMsg "ansiHostInvent1=${ansiHostInvent1}"
debugMsg "ansiPrivKey1=${ansiPrivKey1}"
debugMsg "ansiSshUser1=${ansiSshUser1}"
debugMsg "ansiHostInvent2=${ansiHostInvent2}"
debugMsg "ansiPrivKey2=${ansiPrivKey2}"
debugMsg "ansiSshUser2=${ansiSshUser2}"
debugMsg "skipSrvFileFetch=${skipSrvFileFetch}"
debugMsg "skipClstrSetup=${skipClstrSetup}"
debugMsg "forceClstrUpdate=${forceClstrUpdate}"
debugMsg "tntNsList=${tntNsList}"
debugMsg "forceTntNsUpdate=${forceTntNsUpdate}"

if ! [[ (-f "${ansiHostInvent1}" || -f "$(pwd)/${ansiHostInvent1}") &&
        (-f "${ansiHostInvent2}" || -f "$(pwd)/${ansiHostInvent2}") ]]; then
    echo "  [ERROR] Either of the specified Ansible host inventory files doesn't exist!"
    exit 30
fi

if ! [[ -f ${ansiPrivKey1// } && -f ${ansiPrivKey2// } ]]; then
    echo "  [ERROR] Either of the specified private SSH key files doesn't exsit!"
    exit 40
fi

re='^([[:alnum:]_.-]+/[[:alnum:]_.,-]+)+$'
if ! [[ ${tntNsList} =~ ${re} ]]; then
    echo "[ERROR] Invalid value for the input parameter of 'tntNsList'. Format of 'tenant/namespace,tenant/namespace,...' is expected." 
    exit 50
else
    IFS=',' read -r -a tntNsArr <<< "${tntNsList}"
fi

re1='(true|false)'
if ! [[ (-z ${skipSrvFileFetch// } || ${skipSrvFileFetch} =~ ${re1}) &&
        (-z ${skipClstrSetup// } || ${skipClstrSetup} =~ ${re1}) && 
        (-z ${forceClstrUpdate// } ||${forceClstrUpdate} =~ ${re1}) && 
        (-z ${forceTntNsUpdate// } ||${forceTntNsUpdate} =~ ${re1}) ]]; then
    echo "[ERROR] Invalid value for the following input parameters. Boolean value 'true' or 'false' is expected." 
    echo "        ('-skipSrvFileFetch', '-skipClstrSetup', '-forceClstrUpdate', '-forceTntNsUpdate')"
    exit 60
fi


# Create the working folder structure and clean up the old files
mkdir -p .georep_wd/logs .georep_wd/tmp
rm -f .georep_wd/logs/* .georep_wd/tmp/*


echo
stepCnt=0


#######
# The Pulsar cluster names must be valid
#
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Get the Pulsar cluster names from the provided Ansible host inventory files ..."
pulsarClusterName1=$(grep cluster_name ${ansiHostInvent1} | awk -F= '{print $2}' | tr -d '"')
pulsarClusterName2=$(grep cluster_name ${ansiHostInvent2} | awk -F= '{print $2}' | tr -d '"')
debugMsg "pulsarClusterName1=${pulsarClusterName1}"
debugMsg "pulsarClusterName2=${pulsarClusterName2}"
if [[ -z "${pulsarClusterName1// }" || -z "${pulsarClusterName2// }" || 
      "${pulsarClusterName1// }" == "${pulsarClusterName2// }" ]]; then
    echo "  [ERROR] Invalide Pulsar cluster names: either empty or the same Pulsar cluster name is provided - ${pulsarClusterName1}, ${pulsarClusterName2}!"
    exit 70
fi
echo "   Done!"
echo


#######
# If needed, get client.conf, JWT token, and public CA cert files for the two clusters from the remote server host machine
if [[ "${skipSrvFileFetch}" == "false" ]]; then
    stepCnt=$((stepCnt+1))
    echo "${stepCnt}. Fetch server files for the specified Pulsar clusters."

    echo "   >> fetching for the 1st cluster: ${pulsarClusterName1}"
    ansiExecLogFile1=".georep_wd/logs/${pulsarClusterName1}-georep_getClstrSrvFile.yaml.log"
    ansible-playbook -i ${ansiHostInvent1} georep_getClstrClntCnf.yaml \
                --private-key=${ansiPrivKey1} \
                -u ${ansiSshUser1} -v > ${ansiExecLogFile1} 2>&1
    rtnVal=$?
    if [[ ${rtnVal} -ne 0 ]]; then
        echo "  [ERROR] Failed to get server file from remote for the 1st Pulsar cluster: ${pulsarClusterName1}!"
        exit 80  
    else
        echo "      Complete (rtnVal: ${rtnVal}; log file: ${ansiExecLogFile1} ...)!"
    fi

    echo "   >> fetching for the 2nd cluster: ${pulsarClusterName2}"
    ansiExecLogFile2=".georep_wd/logs/${pulsarClusterName2}-georep_getClstrSrvFile.yaml.log"
    ansible-playbook -i ${ansiHostInvent2} georep_getClstrClntCnf.yaml \
                --private-key=${ansiPrivKey2} \
                -u ${ansiSshUser2} -v > ${ansiExecLogFile2} 2>&1
    rtnVal=$?
    if [[ ${rtnVal} -ne 0 ]]; then
        echo "  [ERROR] Failed to get server files from remote for the 2nd Pulsar cluster: ${pulsarClusterName2}!"
        exit 90  
    else
        echo "      Complete (rtnVal: ${rtnVal}; log file: ${ansiExecLogFile2}!"
    fi
    echo
fi


#######
# Parameter validity check for enabling geo-replication
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Parameter validity check for enabling geo-replication!"

# Check whether the following parameters exist for the 1st cluster
#   'webSvcUrl','brokerSvcUrl', 'authPlugin', 'authParams'
echo "   >> Check \"webSvcUrl\", \"brokerServiceUrl\", and \"authPlugin\" settings for the 1st Pulsar cluster: ${pulsarClusterName1}"
pulsarClientConf1=".georep_wd/${pulsarClusterName1}-client.conf"
if [[ -f "${pulsarClientConf1}" ]]; then
    webSvcUrl1=$(grep -v ^\# ${pulsarClientConf1} | grep webServiceUrl | awk -F= '{print $2}' | tr -d '"')
    IFS=',' read -r -a tmpArr1 <<< "${webSvcUrl1}"
    restApiUrl1=${tmpArr1[0]}
    brokerSvcUrl1=$(grep -v ^\# ${pulsarClientConf1} | grep brokerServiceUrl | awk -F= '{print $2}' | tr -d '"')
    authPlugin1=$(grep -v ^\# ${pulsarClientConf1} | grep authPlugin | awk -F= '{print $2}' | tr -d '"')
    jwtBrkrTokenFilePath1=$(grep -v ^\# ${pulsarClientConf1} | grep authParams | awk -F= '{print $2}' | tr -d '"')
    jwtTokenName1=$(echo ${jwtBrkrTokenFilePath1} | awk -F'/' '{print $NF}')
    trustedBrkrCaCertFilePath1=$(grep -v ^\# ${pulsarClientConf1} | grep tlsTrustCertsFilePath | awk -F= '{print $2}' | tr -d '"')
    trustedBrkrCaCertName1=$(echo ${trustedBrkrCaCertFilePath1} | awk -F'/' '{print $NF}')
else
    echo "      [ERROR] \"client.conf\" file doesn't exist locally for the 1st Pulsar cluster!"
    exit 100 
fi
debugMsg "webSvcUrl1=${webSvcUrl1}"
debugMsg "restApiUrl1=${restApiUrl1}"
debugMsg "brokerSvcUrl1=${brokerSvcUrl1}"
debugMsg "authPlugin1=${authPlugin1}"
debugMsg "jwtBrkrTokenFilePath1=${jwtBrkrTokenFilePath1}"
debugMsg "jwtTokenName1=${jwtTokenName1}"
debugMsg "trustedBrkrCaCertFilePath1=${trustedBrkrCaCertFilePath1}"
debugMsg "trustedBrkrCaCertName1=${trustedBrkrCaCertName1}"
if [[ -z "${webSvcUrl1// }" || -z "${brokerSvcUrl1// }" || -z "${authPlugin1// }" || 
      -z "${jwtBrkrTokenFilePath1// }" || -z "${trustedBrkrCaCertFilePath1// }" ]]; then
    echo "      [ERROR] The following parametres don't exist for the 1st Pulsar cluster!"
    echo "              ('webServiceUrl', 'brokerServiceUrl', 'authPlugin', 'jwtBrkrTokenFilePath', 'trustedBrkrCaCertFilePath')"
    exit 110
fi
echo "      Done!"

# Check if the security files (JWT token and TLS cert) exist locally to connect to the 1st Pulsar cluster
echo "   >> Check \"jwtTokenFile\" and \"tlsTrustCertFile\" settings for the 1st Pulsar cluster: ${pulsarClusterName1}"
localJwtTokenFile1=".georep_wd/${pulsarClusterName1}-${jwtTokenName1}"
localTsTrustCertFile1=".georep_wd/${pulsarClusterName1}-${trustedBrkrCaCertName1}"
debugMsg "localJwtTokenFile1=${localJwtTokenFile1}"
debugMsg "localTsTrustCertFile1=${localTsTrustCertFile1}"
if ! [[ (-f "${localJwtTokenFile1}" || -f "$(pwd)/${localJwtTokenFile1}") &&
        (-f "${localTsTrustCertFile1}" || -f "$(pwd)/${localTsTrustCertFile1}") ]]; then
    echo "      [ERROR] JWT token or TLS CA cert file doesn't exist for the 1st Pulsar cluster!"
    exit 120
fi
echo "      Done!"

# Check whether the following parameters exist for the 2nd cluster
#   'webSvcUrl','brokerSvcUrl', 'authPlugin', 'authParams'
echo "   >> Check \"webSvcUrl\", \"brokerServiceUrl\", and \"authPlugin\" settings for the 2nd Pulsar cluster: ${pulsarClusterName2}"
pulsarClientConf2=".georep_wd/${pulsarClusterName2}-client.conf"
if [[ -f "${pulsarClientConf2}" ]]; then
    webSvcUrl2=$(grep -v ^\# ${pulsarClientConf2} | grep webServiceUrl | awk -F= '{print $2}' | tr -d '"')
    IFS=',' read -r -a tmpArr2 <<< "${webSvcUrl2}"
    restApiUrl2=${tmpArr2[0]}
    brokerSvcUrl2=$(grep -v ^\# ${pulsarClientConf2} | grep brokerServiceUrl | awk -F= '{print $2}' | tr -d '"')
    authPlugin2=$(grep -v ^\# ${pulsarClientConf2} | grep authPlugin | awk -F= '{print $2}' | tr -d '"')
    jwtBrkrTokenFilePath2=$(grep -v ^\# ${pulsarClientConf2} | grep authParams | awk -F= '{print $2}' | tr -d '"')
    jwtTokenName2=$(echo ${jwtBrkrTokenFilePath2} | awk -F'/' '{print $NF}')
    trustedBrkrCaCertFilePath2=$(grep -v ^\# ${pulsarClientConf2} | grep tlsTrustCertsFilePath | awk -F= '{print $2}' | tr -d '"')
    trustedBrkrCaCertName2=$(echo ${trustedBrkrCaCertFilePath2} | awk -F'/' '{print $NF}')
else
    echo "      [ERROR] \"client.conf\" file doesn't exist locally for the 2nd Pulsar cluster: : ${pulsarClusterName2}!"
    exit 130 
fi
debugMsg "webSvcUrl2=${webSvcUrl2}"
debugMsg "restApiUrl2=${restApiUrl2}"
debugMsg "brokerSvcUrl2=${brokerSvcUrl2}"
debugMsg "authPlugin2=${authPlugin2}"
debugMsg "jwtBrkrTokenFilePath2=${jwtBrkrTokenFilePath2}"
debugMsg "jwtTokenName2=${jwtTokenName2}"
debugMsg "trustedBrkrCaCertFilePath2=${trustedBrkrCaCertFilePath2}"
debugMsg "trustedBrkrCaCertName2=${trustedBrkrCaCertName2}"
if [[ -z "${webSvcUrl2// }" || -z "${brokerSvcUrl2// }" || -z "${authPlugin2// }" || 
      -z "${jwtBrkrTokenFilePath2// }" || -z "${trustedBrkrCaCertFilePath2// }" ]]; then
    echo "      [ERROR] The following parametres don't exist for the 2nd Pulsar cluster!"
    echo "              ('webServiceUrl', 'brokerServiceUrl', 'authPlugin', 'jwtBrkrTokenFilePath', 'trustedBrkrCaCertFilePath')"
    exit 140
fi
echo "      Done!"

# Check if the security files (JWT token and TLS cert) exist locally to connect to the 2nd Pulsar cluster
echo "   >> Check local \"jwtTokenFile\" and \"tlsTrustCertFile\" settings for the 2nd Pulsar cluster: ${pulsarClusterName2}"
localJwtTokenFile2=".georep_wd/${pulsarClusterName2}-${jwtTokenName2}"
localTsTrustCertFile2=".georep_wd/${pulsarClusterName2}-${trustedBrkrCaCertName2}"
debugMsg "localJwtTokenFile2=${localJwtTokenFile2}"
debugMsg "localTsTrustCertFile2=${localTsTrustCertFile2}"
if ! [[ (-f "${localJwtTokenFile2}" || -f "$(pwd)/${localJwtTokenFile2}") &&
        (-f "${localTsTrustCertFile2}" || -f "$(pwd)/${localTsTrustCertFile2}") ]]; then
    echo "      [ERROR] The specified JWT token or TLS cert file for the 2nd Pulsar cluster doesn't exist!"
    exit 150
fi
echo "      Done!"
echo


#######
# Ready to set up geo-replication on the Pulsar cluster
#
setupRemoteClstrOnLocal () {
    local firstClstrName=${1}
    local firstClstrRestApiUrl=${2}
    local firstClstrJwtTokenFile=${3}
    local firstClstrCaCertFile=${4}
    local secondClstrName=${5}
    local secondClstrWebSvcUrl=${6}
    local secondClstrBrkrSvcurl=${7}
    local secondClstrAuthPlugin=${8}
    local secondClstrJwtTokenFile=${9}
    local secondClstrCaCertFile=${10}
    local errorCode=${11}

    echo "   >> Check if the remote cluster \"${secondClstrName}\" has already existed on the local cluster: ${firstClstrName}"
    local curlCmdGetClstrList="curl -sS -X GET \
    --url '${firstClstrRestApiUrl}/admin/v2/clusters' \
    --cacert '${firstClstrCaCertFile}' \
    --header 'Authorization: Bearer $(cat ${firstClstrJwtTokenFile})' \
    --write-out '%{http_code}' \
    --output '.georep_wd/tmp/${firstClstrName}-curlCmdGetClstrListOut.txt'"
    debugMsg "curlCmdGetClstrList=${curlCmdGetClstrList}"

    local responseCode=$(eval ${curlCmdGetClstrList})
    if [[ ${responseCode} -ne 200 ]]; then
        echo "      [ERROR] Rest API call failure with response code: ${responseCode}"
        exit ${errorCode}
    fi

    local clstrListStr=$(cat .georep_wd/tmp/${firstClstrName}-curlCmdGetClstrListOut.txt)
    debugMsg "clstrList=${clstrListStr}"

    local curlCrtUpdClstrCmdTerm=PUT
    local curlCrtUpdClstrCmdDescVerb="Create"
    local remoteNameExists="No"
    if [[ "${clstrListStr}" =~ "${secondClstrName}" ]]; then
        curlCrtUpdClstrCmdTerm=POST
        curlCrtUpdClstrCmdDescVerb="Update"
        remoteNameExists="Yes"
    fi
    echo "      Complete (response code: ${responseCode}; remote clsuter name exists: ${remoteNameExists}/${clstrListStr})!"

    if [[ "${curlCrtUpdClstrCmdTerm}" == "PUT" || "${forceClstrUpdate}" == "true" ]]; then
        echo "   >> ${curlCrtUpdClstrCmdDescVerb} the remote cluster \"${secondClstrName}\" on the local cluster: ${firstClstrName}"
        local curlCrtUpdClstrCmdLog=".georep_wd/logs/${firstClstrName}-curlUpdate.log"
        local curlCrtUpdClstrCmd="curl -sS -X ${curlCrtUpdClstrCmdTerm} \
        --url '${firstClstrRestApiUrl}/admin/v2/clusters/${secondClstrName}' \
        --cacert '${firstClstrCaCertFile}' \
        --header 'Authorization: Bearer $(cat ${firstClstrJwtTokenFile})' \
        --header 'Content-Type: application/json' \
        --data '{ \"serviceUrlTls\": \"${secondClstrWebSvcUrl}\", \
                  \"brokerServiceUrlTls\": \"${secondClstrBrkrSvcurl}\", \
                  \"authenticationPlugin\": \"${secondClstrAuthPlugin}\", \
                  \"authenticationParameters\": \"token:$(cat ${secondClstrJwtTokenFile})\", \
                  \"brokerClientTrustCertsFilePath\": \"${secondClstrCaCertFile}\" }' \
        --write-out '%{http_code}'"
        debugMsg "curlCrtUpdClstrCmd=${curlCrtUpdClstrCmd}"

        responseCode=$(eval ${curlCrtUpdClstrCmd})
        if [[ ${responseCode} -ne 204 ]]; then
            echo "      [ERROR] Rest API call failure with response code: ${responseCode}"
            exit ${errorCode}
        fi

        echo "      Complete (response code: ${responseCode})!"
        echo
    fi
}

# Update cluster setup only when needed
if [[ "${skipClstrSetup}" == "false" ]]; then
    # Set up the geo-replication on the 1st clsuter
    stepCnt=$((stepCnt+1))
    echo "${stepCnt}. Set up remote cluster \"${pulsarClusterName2}\" on the loocal cluster: ${pulsarClusterName1}"
    setupRemoteClstrOnLocal \
        "${pulsarClusterName1}" \
        "${restApiUrl1}" \
        "${localJwtTokenFile1}" \
        "${localTsTrustCertFile1}" \
        "${pulsarClusterName2}" \
        "${webSvcUrl2}" \
        "${brokerSvcUrl2}" \
        "${authPlugin2}" \
        "${localJwtTokenFile2}" \
        "${trustedBrkrCaCertFilePath2}" \
        160
    echo

    # Set up the geo-replication on the 2nd clsuter
    stepCnt=$((stepCnt+1))
    echo "${stepCnt}. Set up remote cluster \"${pulsarClusterName1}\" on the loocal cluster: ${pulsarClusterName2}"
    setupRemoteClstrOnLocal \
        "${pulsarClusterName2}" \
        "${restApiUrl2}" \
        "${localJwtTokenFile2}" \
        "${localTsTrustCertFile2}" \
        "${pulsarClusterName1}" \
        "${webSvcUrl1}" \
        "${brokerSvcUrl1}" \
        "${authPlugin1}" \
        "${localJwtTokenFile1}" \
        "${trustedBrkrCaCertFilePath1}" \
        170
    echo
fi


#######
# Create tenants and namespaces across 2 Pulsar clusters
#
checkTntExistence () {
    local clstrName=${1}
    local tenantName=${2}
    local clstrRestApiUrl=${3}
    local clstrJwtTokenFile=${4}
    local clstrCaCertFile=${5}
    local errorCode=${6}

    echo "   >> Check if tenant \"${tenantName}\" exists on cluster: ${clstrName}"
    local curlCmdGetTntList="curl -sS -X GET \
    --url '${clstrRestApiUrl}/admin/v2/tenants' \
    --cacert '$(pwd)/${clstrCaCertFile}' \
    --header 'Authorization: Bearer $(cat ${clstrJwtTokenFile})' \
    --write-out '%{http_code}' \
    --output '.georep_wd/tmp/${clstrName}-curlCmdGetTntList.txt'"
    debugMsg "curlCmdGetResourceList=${curlCmdGetTntList}"

    local responseCode=$(eval ${curlCmdGetTntList})
    if [[ ${responseCode} -ne 200 ]]; then
        echo "      [ERROR] Rest API call failure with response code: ${responseCode}"
        exit ${errorCode}
    fi

    local tntListStr=$(cat .georep_wd/tmp/${clstrName}-curlCmdGetTntList.txt)
    debugMsg "resourceListStr=${tntListStr}"

    if [[ "${tntListStr}" =~ "${tenantName}" ]]; then
        tntExists="Yes"
    else
        tntExists="No"
    fi
    echo "      Complete (response code: ${responseCode}; tenant exists: ${tntExists} - ${tntListStr})!"

    if [[ "${tntExists}" == "Yes" ]]; then
        return 1
    else
        return 0
    fi
}

crtUpdTnt () {
    local firstClstrName=${1}
    local secondClstrName=${2}
    local tntExistence=${3}
    local tenantName=${4}
    local clstrRestApiUrl=${5}
    local clstrJwtTokenFile=${6}
    local clstrCaCertFile=${7}
    local errorCode=${8}

    local curlCmdTerm=PUT
    local culCmdDescVerb="Create"
    if [[ ${tntExistence} -eq 1 ]]; then
        curlCmdTerm=POST
        culCmdDescVerb="Update"
    fi

    echo "   >> ${culCmdDescVerb} tenant \"${tenantName}\" on cluster: ${firstClstrName}"
    local curlCmdTntCrtUpd="curl -sS -X ${curlCmdTerm} \
    --url '${clstrRestApiUrl}/admin/v2/tenants/${tenantName}' \
    --cacert '$(pwd)/${clstrCaCertFile}' \
    --header 'Authorization: Bearer $(cat ${clstrJwtTokenFile})' \
    --header 'Content-Type: application/json' \
    --data '{ \"adminRoles\": [\"${tenantName}-admin\"], \
              \"allowedClusters\": [\"${firstClstrName}\",\"${secondClstrName}\"] }' \
    --write-out '%{http_code}'"
    debugMsg "curlCmdTntCrtUpd=${curlCmdTntCrtUpd}"

    local responseCode=$(eval ${curlCmdTntCrtUpd})
    if [[ ${responseCode} -ne 204 ]]; then
        echo "      [ERROR] Rest API call failure with response code: ${responseCode}"
        exit ${errorCode}
    fi

    echo "      Complete (response code: ${responseCode})!"
    echo
}

checkNsExistence () {
    local clstrName=${1}
    local tenantName=${2}
    local namespaceName=${3}
    local clstrRestApiUrl=${4}
    local clstrJwtTokenFile=${5}
    local clstrCaCertFile=${6}
    local errorCode=${7}

    echo "   >> Check if namespace \"${tenantName}/${namespaceName}\" exists on cluster: ${clstrName}"
    local curlCmdGetNsList="curl -sS -X GET \
    --url '${clstrRestApiUrl}/admin/v2/namespaces/${tenantName}' \
    --cacert '$(pwd)/${clstrCaCertFile}' \
    --header 'Authorization: Bearer $(cat ${clstrJwtTokenFile})' \
    --write-out '%{http_code}' \
    --output '.georep_wd/tmp/${clstrName}-curlCmdGetNsList.txt'"
    debugMsg "curlCmdGetResourceList=${curlCmdGetNsList}"

    local responseCode=$(eval ${curlCmdGetNsList})
    if [[ ${responseCode} -ne 200 ]]; then
        echo "      [ERROR] Rest API call failure with response code: ${responseCode}"
        exit ${errorCode}
    fi

    local nsListStr=$(cat .georep_wd/tmp/${clstrName}-curlCmdGetNsList.txt)
    debugMsg "resourceListStr=${nsListStr}"

    if [[ "${nsListStr}" =~ "${tenantName}/${namespaceName}" ]]; then
        nsExists="Yes"
    else
        nsExists="No"
    fi
    echo "      Complete (response code: ${responseCode}; namespace exists: ${nsExists} - ${nsListStr})!"

    if [[ "${nsExists}" == "Yes" ]]; then
        return 1
    else
        return 0
    fi
}

crtUpdNs () {
    local firstClstrName=${1}
    local secondClstrName=${2}
    local tntExistence=${3}
    local tenantName=${4}
    local namespaceName=${5}
    local clstrRestApiUrl=${6}
    local clstrJwtTokenFile=${7}
    local clstrCaCertFile=${8}
    local errorCode=${9}
    
    local culCmdDescVerb="Create"
    local curlCmdNsCrtUpd="curl -sS -X PUT \
        --url '${clstrRestApiUrl}/admin/v2/namespaces/${tenantName}/${namespaceName}' \
        --cacert '$(pwd)/${clstrCaCertFile}' \
        --header 'Authorization: Bearer $(cat ${clstrJwtTokenFile})' \
        --header 'Content-Type: application/json' \
        --data '{ \"replication_clusters\": [\"${firstClstrName}\",\"${secondClstrName}\"] }' \
        --write-out '%{http_code}'"
        
    if [[ ${tntExistence} -eq 1 ]]; then
        culCmdDescVerb="Update"

        curlCmdNsCrtUpd="curl -sS -X POST \
        --url '${clstrRestApiUrl}/admin/v2/namespaces/${tenantName}/${namespaceName}/replication' \
        --cacert '$(pwd)/${clstrCaCertFile}' \
        --header 'Authorization: Bearer $(cat ${clstrJwtTokenFile})' \
        --header 'Content-Type: application/json' \
        --data '[\"${firstClstrName}\",\"${secondClstrName}\"]' \
        --write-out '%{http_code}'"
    fi

    echo "   >> ${culCmdDescVerb} namespace \"${tenantName}/${namespaceName}\" on cluster: ${firstClstrName}"

    debugMsg "curlCmdTntCrtUpd=${curlCmdNsCrtUpd}"

    local responseCode=$(eval ${curlCmdNsCrtUpd})
    if [[ ${responseCode} -ne 204 ]]; then
        echo "      [ERROR] Rest API call failure with response code: ${responseCode}"
        exit ${errorCode}
    fi

    echo "      Complete (response code: ${responseCode})!"
}

stepCnt=$((stepCnt+1))
echo "${stepCnt}. Create/Update the specified tenants and namespeces on each Pulsar cluster"

processed_TntNs_List=""
processed_Tnt_List=""
for tntNs in "${tntNsArr[@]}"; do
    if [[ -z "${processed_TntNs_List}" ||
          (-n "${tntNs// }" && ! "${processed_TntNs_List}" =~ "${tntNs}") ]]; then
        tntName=$(echo ${tntNs} | awk -F/ '{print $1}')
        nsName=$(echo ${tntNs} | awk -F/ '{print $2}')

        if [[ -z "${processed_Tnt_List}" ||
              (-n "${tntName// }" && ! "${processed_Tnt_List}" =~ "${tntName}") ]]; then
            
            echo "   Process tenant \"${tntName}\" ..."  
            # Check if the tenant exists on the 1st Pulsar cluster
            checkTntExistence \
                "${pulsarClusterName1}" \
                "${tntName}" \
                "${restApiUrl1}" \
                "${localJwtTokenFile1}" \
                "${localTsTrustCertFile1}" \
                180
            tntOnCluster1=$?
            
            # Create or update the tenant on the 1st Pulsar cluster
            if [[ ${tntOnCluster1} -eq 0 || "${forceTntNsUpdate}" == "true" ]]; then
                crtUpdTnt \
                    ${pulsarClusterName1} \
                    ${pulsarClusterName2} \
                    ${tntOnCluster1} \
                    ${tntName} \
                    ${restApiUrl1} \
                    ${localJwtTokenFile1} \
                    ${localTsTrustCertFile1} \
                    190
            fi

            # Check if the tenant exists on the 2nd Pulsar cluster
            checkTntExistence \
                "${pulsarClusterName2}" \
                "${tntName}" \
                "${restApiUrl2}" \
                "${localJwtTokenFile2}" \
                "${localTsTrustCertFile2}" \
                200
            tntOnCluster2=$?
            
            # Create or update the tenant on the 2nd Pulsar cluster
            if [[ ${tntOnCluster2} -eq 0 || "${forceTntNsUpdate}" == "true" ]]; then
                crtUpdTnt \
                    ${pulsarClusterName2} \
                    ${pulsarClusterName1} \
                    ${tntOnCluster2} \
                    ${tntName} \
                    ${restApiUrl2} \
                    ${localJwtTokenFile2} \
                    ${localTsTrustCertFile2} \
                    210
            fi           

            processed_Tnt_List="${processed_Tnt_List} ${tntName}"
            echo
        fi

        echo "   Process namespace \"${tntName}/${nsName}\" ..."  

        # Check if the namespace for the tenant exists on the 1st Pulsar cluster
        checkNsExistence \
            "${pulsarClusterName1}" \
            "${tntName}" \
            "${nsName}" \
            "${restApiUrl1}" \
            "${localJwtTokenFile1}" \
            "${localTsTrustCertFile1}" \
            220
        nsOnCluster1=$?

        # Create or update the namespace for the tenant on the 1st Pulsar cluster
        if [[ ${nsOnCluster1} -eq 0 || "${forceTntNsUpdate}" == "true" ]]; then
            crtUpdNs \
                ${pulsarClusterName1} \
                ${pulsarClusterName2} \
                ${tntOnCluster1} \
                ${tntName} \
                ${nsName} \
                ${restApiUrl1} \
                ${localJwtTokenFile1} \
                ${localTsTrustCertFile1} \
                230
        fi

        # Check if the namespace for the tenant exists on the 2nd Pulsar cluster
        checkNsExistence \
            "${pulsarClusterName2}" \
            "${tntName}" \
            "${nsName}" \
            "${restApiUrl2}" \
            "${localJwtTokenFile2}" \
            "${localTsTrustCertFile2}" \
            240
        nsOnCluster2=$?

        # Create or update the namespace for the tenant on the 2nd Pulsar cluster
        if [[ ${nsOnCluster2} -eq 0 || "${forceTntNsUpdate}" == "true" ]]; then
            crtUpdNs \
                ${pulsarClusterName2} \
                ${pulsarClusterName1} \
                ${tntOnCluster1} \
                ${tntName} \
                ${nsName} \
                ${restApiUrl2} \
                ${localJwtTokenFile2} \
                ${localTsTrustCertFile2} \
                250
        fi        

        processed_TntNs_List="${processed_TntNs_List} ${tntNs}"
        echo
    fi
done

exit