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
   echo "                                  [-forceUpdate <force_update>]"
   echo "       -h   : Show usage info"
   echo "       -ansiHostInvent1 : Ansible host inventory file for Pulsar cluster 1"
   echo "       -ansiPrivKey1    : SSH private key to connect to Pulsar cluster 1"
   echo "       -ansiSshUser1    : SSH user to connect to Pulsar cluster 1"
   echo "       -ansiHostInvent2 : Ansible host inventory file for Pulsar cluster 2"
   echo "       -ansiPrivKey2    : SSH private key to connect to Pulsar cluster 2"
   echo "       -ansiSshUser2    : SSH user to connect to Pulsar cluster 2"
   echo "       [-forceUpdate]   : Whether to force update existing remote cluster definition!"
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

if [[ $# -eq 0 || $# -gt 14 ]]; then
   usage
   exit 10
fi

forceUpdate=false
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -ansiHostInvent1) ansiHostInvent1=$2; shift ;;
      -ansiPrivKey1) ansiPrivKey1=$2; shift ;;
      -ansiSshUser1) ansiSshUser1=$2; shift ;;
      -ansiHostInvent2) ansiHostInvent2=$2; shift ;;
      -ansiPrivKey2) ansiPrivKey2=$2; shift ;;
      -ansiSshUser2) ansiSshUser2=$2; shift ;;
      -forceUpdate) forceUpdate=$(echo $2 | tr '[:upper:]' '[:lower:]'); shift ;;
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
debugMsg "forceUpdate=${forceUpdate}"

if [[ -n "${forceUpdate// }" ]]; then
    re='(true|false)'
    if ! [[ ${forceUpdate} =~ $re ]]; then
        echo "[ERROR] Invalid value for the following input parameter of 'forceUpdate'. Value 'true' or 'false' is expected." 
        exit 30
    fi
fi

echo
stepCnt=0

mkdir -p .georep_wd/logs .georep_wd/tmp


#######
# Must provide the Ansible host inventory files used to deploy the two Pulsar clusters
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Check if the provided Ansible host inventory files are valid ..."
if ! [[ (-f "${ansiHostInvent1}" || -f "$(pwd)/${ansiHostInvent1}") &&
        (-f "${ansiHostInvent2}" || -f "$(pwd)/${ansiHostInvent2}") ]]; then
    echo "  [ERROR] The specified Ansible host inventory file (used for Pulsar cluster deplyment) doesn't exist!"
    exit 40
fi
echo "   Done!"
echo


#######
# The Pulsar cluster names must be valid
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Get the Pulsar cluster names from the provided Ansible host inventory files ..."
pulsarClusterName1=$(grep cluster_name ${ansiHostInvent1} | awk -F= '{print $2}' | tr -d '"')
pulsarClusterName2=$(grep cluster_name ${ansiHostInvent2} | awk -F= '{print $2}' | tr -d '"')
debugMsg "pulsarClusterName1=${pulsarClusterName1}"
debugMsg "pulsarClusterName2=${pulsarClusterName2}"
if [[ -z "${pulsarClusterName1// }" || -z "${pulsarClusterName2// }" || 
      "${pulsarClusterName1// }" == "${pulsarClusterName2// }" ]]; then
    echo "  [ERROR] Invalide Pulsar cluster names: either empty or the same Pulsar cluster names - ${pulsarClusterName1}, ${pulsarClusterName2}!"
    exit 50
fi
echo "   Done!"
echo


#######
# Get the service URLs and authPlugin settings for the 1st Pulsar cluster
ansiExecLogFile1=".georep_wd/logs/${pulsarClusterName1}-georep_getClstrClntCnf.yaml.log"
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Fetch \"client.conf\" file for the 1st Pulsar cluster: ${pulsarClusterName1}"
if ! [[ -f ${ansiPrivKey1// } ]]; then
    echo "  [ERROR] The specified private SSH key file for the 1st Pulsar cluster doesn't exist !"
    exit 60
fi
ansible-playbook -i ${ansiHostInvent1} georep_getClstrClntCnf.yaml \
            --private-key=${ansiPrivKey1} \
            -u ${ansiSshUser1} -v > ${ansiExecLogFile1} 2>&1
echo "   Complete (rtnVal: $?; log file: ${ansiExecLogFile1} ...)!"

echo "   >> Check \"webSvcUrl\", \"brokerServiceUrl\", and security settings for the 1st Pulsar cluster: ${pulsarClusterName1}"
pulsarClientConf1=".georep_wd/${pulsarClusterName1}-client.conf"
if [[ -f "${pulsarClientConf1}" ]]; then
    webSvcUrl1=$(grep -v ^\# ${pulsarClientConf1} | grep webServiceUrl | awk -F= '{print $2}' | tr -d '"')
    brokerSvcUrl1=$(grep -v ^\# ${pulsarClientConf1} | grep brokerServiceUrl | awk -F= '{print $2}' | tr -d '"')
    authPlugin1=$(grep -v ^\# ${pulsarClientConf1} | grep authPlugin | awk -F= '{print $2}' | tr -d '"')
    authParams1=$(grep -v ^\# ${pulsarClientConf1} | grep authParams | awk -F= '{print $2}' | tr -d '"')
    trustedBrkrCaCert1=$(grep -v ^\# ${pulsarClientConf1} | grep tlsTrustCertsFilePath | awk -F= '{print $2}' | tr -d '"')
fi
debugMsg "webSvcUrl1=${webSvcUrl1}"
debugMsg "brokerSvcUrl1=${brokerSvcUrl1}"
debugMsg "authPlugin1=${authPlugin1}"
if [[ -z "${webSvcUrl1// }" || -z "${brokerSvcUrl1// }" || 
      -z "${authPlugin1// }" || -z "${authParams1// }" ]]; then
    echo "  [ERROR] \"webServiceUrl\", \"brokerServiceUrl\", or security related settings for the 1st Pulsar cluster doesn't exist!"
    exit 70
fi
echo "      Done!"

# Check if the security files (JWT token and TLS cert) exist locally to connect to the 1st Pulsar cluster
echo "   >> Check local \"jwtTokenFile\" and \"tlsTrustCertFile\" settings for the 1st Pulsar cluster: ${pulsarClusterName1}"
jwtTokenFile1="bash/security/authentication/jwt/staging/token/${pulsarClusterName1}/brokers/cluster_brkr_admin.jwt"
tlsTrustCertFile1="bash/security/intransit_encryption/staging/certs/broker_ca.cert.pem"
debugMsg "jwtTokenFile1=${jwtTokenFile1}"
debugMsg "tlsTrustCertFile1=${tlsTrustCertFile1}"
if ! [[ (-f "${jwtTokenFile1}" || -f "$(pwd)/${jwtTokenFile1}") &&
        (-f "${tlsTrustCertFile1}" || -f "$(pwd)/${tlsTrustCertFile1}") ]]; then
    echo "  [ERROR] The specified JWT token or TLS cert file for the 1st Pulsar cluster doesn't exist!"
    exit 80
fi
echo "      Done!"
echo


#######
# Get the service URLs and authPlugin settings for the 2nd Pulsar cluster
ansiExecLogFile2=".georep_wd/logs/${pulsarClusterName2}-georep_getClstrClntCnf.yaml.log"
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Fetch \"client.conf\" file for the 2nd Pulsar cluster: ${pulsarClusterName2}"
if ! [[ -f ${ansiPrivKey2// } ]]; then
    echo "  [ERROR] The specified private SSH key file for the 2nd Pulsar cluster doesn't exist!"
    exit 90
fi
ansible-playbook -i ${ansiHostInvent2} georep_getClstrClntCnf.yaml \
            --private-key=${ansiPrivKey2} \
            -u ${ansiSshUser2} -v > ${ansiExecLogFile2} 2>&1
echo "   Complete (rtnVal: $?; log file: ${ansiExecLogFile2}!"

echo "   >> Check \"webSvcUrl\", \"brokerServiceUrl\", and security related settings for the 2nd Pulsar cluster: ${pulsarClusterName2}"
pulsarClientConf2=".georep_wd/${pulsarClusterName2}-client.conf"
if [[ -f "${pulsarClientConf2}" ]]; then
    webSvcUrl2=$(grep -v ^\# ${pulsarClientConf2} | grep webServiceUrl | awk -F= '{print $2}' | tr -d '"')
    brokerSvcUrl2=$(grep -v ^\# ${pulsarClientConf2} | grep brokerServiceUrl | awk -F= '{print $2}' | tr -d '"')
    authPlugin2=$(grep -v ^\# ${pulsarClientConf2} | grep authPlugin | awk -F= '{print $2}' | tr -d '"')
    authParams2=$(grep -v ^\# ${pulsarClientConf2} | grep authParams | awk -F= '{print $2}' | tr -d '"')
    trustedBrkrCaCert2=$(grep -v ^\# ${pulsarClientConf2} | grep tlsTrustCertsFilePath | awk -F= '{print $2}' | tr -d '"')
fi
debugMsg "webSvcUrl2=${webSvcUrl2}"
debugMsg "brokerSvcUrl2=${brokerSvcUrl2}"
debugMsg "authPlugin2=${authPlugin2}"
if [[ -z "${webSvcUrl2// }" || -z "${brokerSvcUrl2// }" || 
      -z "${authPlugin2// }" || -z "${authParams2// }" ]]; then
    echo "  [ERROR] \"webServiceUrl\", \"brokerServiceUrl\", or \"authPlugin\" for the 2nd Pulsar cluster doesn't exist!"
    exit 100
fi
echo "      Done!"

# Check if the security files (JWT token and TLS cert) exist locally to connect to the 2nd Pulsar cluster
echo "   >> Check local \"jwtTokenFile\" and \"tlsTrustCertFile\" settings for the 2nd Pulsar cluster: ${pulsarClusterName2}"
jwtTokenFile2="bash/security/authentication/jwt/staging/token/${pulsarClusterName1}/brokers/cluster_brkr_admin.jwt"
tlsTrustCertFile2="bash/security/intransit_encryption/staging/certs/broker_ca.cert.pem"
debugMsg "jwtTokenFile2=${jwtTokenFile2}"
debugMsg "tlsTrustCertFile2=${tlsTrustCertFile2}"
if ! [[ (-f "${jwtTokenFile2}" || -f "$(pwd)/${jwtTokenFile2}") &&
        (-f "${tlsTrustCertFile2}" || -f "$(pwd)/${tlsTrustCertFile2}") ]]; then
    echo "  [ERROR] The specified JWT token or TLS cert file for the 2nd Pulsar cluster doesn't exist!"
    exit 110
fi
echo "      Done!"
echo


#######
# Ready to set up geo-replication on the Pulsar cluster
setupGeoRepOnLocal () {
    local localClstrName=${1}
    local localClstrWebSvcUrl=${2}
    local localClstrJwtTokenFile=${3}
    local localClstrCaCertFile=${4}
    local remoteClstrName=${5}
    local remoteClstrWebSvcUrl=${6}
    local remoteClstrBrkrSvcurl=${7}
    local remoteClstrAuthPlugin=${8}
    local remoteClstrJwtTokenFile=${9}
    local remoteClstrCaCertFile=${10}
    local errorCode=${11}

    echo "   >> Check if the remote cluster \"${remoteClstrName}\" has already existed on the local cluster: ${localClstrName}"
    curlCmdGet="curl -sS -X GET \
    --url '${localClstrWebSvcUrl}/admin/v2/clusters' \
    --cacert '$(pwd)/${localClstrCaCertFile}' \
    --header 'Authorization: Bearer $(cat ${localClstrJwtTokenFile})' \
    --write-out '%{http_code}' \
    --output '.georep_wd/tmp/${localClstrName}-curlCmdGetOut.txt'"
    debugMsg "curlCmdGet=${curlCmdGet}"

    responseCode=$(eval ${curlCmdGet})
    if [[ ${responseCode} -ne 200 ]]; then
        echo "      [ERROR] Rest API call failure with response code: ${responseCode}"
        exit ${errorCode}
    fi

    clstrListStr=$(cat .georep_wd/tmp/${localClstrName}-curlCmdGetOut.txt)
    debugMsg "clstrList=${clstrListStr}"

    if [[ "${clstrListStr}" =~ .*"${remoteClstrName}".* ]]; then
        curlUpdateCmdTerm=POST
        curlUpdateCmdDescVerb="Update"
        remoteNameExists="Yes"
    else
        curlUpdateCmdTerm=PUT
        curlUpdateCmdDescVerb="Create"
        remoteNameExists="No"
    fi
    echo "      Complete (response code: ${responseCode}; remote clsuter name exists: ${remoteNameExists}/${clstrListStr})!"

    if [[ "${curlUpdateCmdTerm}" == "PUT" || "${forceUpdate}" == "true" ]]; then
        echo "   >> ${curlUpdateCmdDescVerb} the remote cluster \"${remoteClstrName}\" on the local cluster: ${localClstrName}"
        curlCmdUpdateLog=".georep_wd/logs/${localClstrName}-curlUpdate.log"
        curlUpdateCmd="curl -sS -X ${curlUpdateCmdTerm} \
        --url '${localClstrWebSvcUrl}/admin/v2/clusters/${remoteClstrName}' \
        --cacert '$(pwd)/${localClstrCaCertFile}' \
        --header 'Authorization: Bearer $(cat ${localClstrJwtTokenFile})' \
        --header 'Content-Type: application/json' \
        --data '{ \
            \"brokerClientTlsEnabled\": \"true\", \
            \"serviceUrlTls\": \"${remoteClstrWebSvcUrl}\", \
            \"brokerServiceUrlTls\": \"${remoteClstrBrkrSvcurl}\", \
            \"authenticationPlugin\": \"${remoteClstrAuthPlugin}\", \
            \"authenticationParameters\": \"token:$(cat ${remoteClstrJwtTokenFile})\", \
            \"brokerClientTrustCertsFilePath\": \"${remoteClstrCaCertFile}\" 
        }' \
        --write-out '%{http_code}'"
        debugMsg "curlUpdateCmd=${curlUpdateCmd}"

        responseCode=$(eval ${curlUpdateCmd})
        if [[ ${responseCode} -ne 204 ]]; then
            echo "      [ERROR] Rest API call failure with response code: ${responseCode}"
            exit ${errorCode}
        fi

        echo "      Complete (response code: ${responseCode})!"
        echo
    fi
}


# Set up the geo-replication on the 1st clsuter
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Set up remote cluster \"${pulsarClusterName1}\" on the loocal cluster: ${pulsarClusterName2}"
setupGeoRepOnLocal \
    "${pulsarClusterName1}" \
    "${webSvcUrl1}" \
    "${jwtTokenFile1}" \
    "${tlsTrustCertFile1}" \
    "${pulsarClusterName2}" \
    "${webSvcUrl2}" \
    "${brokerSvcUrl2}" \
    "${authPlugin2}" \
    "${jwtTokenFile2}" \
    "${tlsTrustCertFile2}" \
    120
echo

# Set up the geo-replication on the 2nd clsuter
stepCnt=$((stepCnt+1))
echo "${stepCnt}. Set up remote cluster \"${pulsarClusterName1}\" on the loocal cluster: ${pulsarClusterName2}"
setupGeoRepOnLocal \
    "${pulsarClusterName2}" \
    "${webSvcUrl2}" \
    "${jwtTokenFile2}" \
    "${tlsTrustCertFile2}" \
    "${pulsarClusterName1}" \
    "${webSvcUrl1}" \
    "${brokerSvcUrl1}" \
    "${authPlugin1}" \
    "${jwtTokenFile1}" \
    "${tlsTrustCertFile1}" \
    130
echo