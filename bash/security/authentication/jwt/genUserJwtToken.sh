#! /bin/bash


#
# NOTE: this script is used for createing a JWT token that is used
#       for Pulsar user authentication
#
#


# Check if "pulsar" executable is available
whichPulsar=$(which pulsar)
if [[ "${whichPulsar}" == "" || "${whichPulsar}" == *"not found"* ]]; then
  echo "Can't find \"pulsar\" executable which is necessary to create JWT tokens"
  exit 10
fi

usage() {
   echo
   echo "Usage: genUserJwtToken.sh [-h] [-r] \
                                   -clst_name <pulsar_cluster_name> \
                                   -host_type <srv_host_type> \
                                   -user_list <tokenUserList>"
   echo "       -h   : show usage info"
   echo "       [-r] : reuse existing token generation key pair if it already exists"
   echo "       -clst_name <pulsar_cluster_name> : Pulsar cluster name"
   echo "       -host_type <srv_host_type>: Pulsar server host type that needs to set up JWT tokens (e.g. broker, functions_worker)"
   echo "       -user_list <tokenUserList> : User name list (comma separated) that need JWT tokens"
   echo
}

if [[ $# -eq 0 || $# -gt 7 ]]; then
   usage
   exit 20
fi

reuseKey=0
srvHostType=""
pulsarClusterName=""
tokenUserNameList=""
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -r) reuseKey=1; ;;
      -clst_name) pulsarClusterName="$2"; shift ;;
      -host_type) srvHostType="$2"; shift ;;
      -user_list) tokenUserNameList="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

if [[ "${srvHostType}" == ""  ]]; then
  echo "[ERROR] Pulsar server host type can't be empty" 
  exit 30
fi

if [[ "${pulsarClusterName}" == ""  ]]; then
  echo "Pulsar cluster name can't be empty" 
  exit 40
fi

if [[ "${tokenUserNameList=""}" == ""  ]]; then
  echo "Token user name list can't be empty" 
  exit 50
fi

PRIV_KEY="${pulsarClusterName}_jwt_private.key"
PUB_KEY="${pulsarClusterName}_jwt_public.key"

mkdir -p staging
cd staging

mkdir -p key token/${srvHostType}s

CUR_DIR=$(pwd)
stepCnt=0

# Create a public/private key pair if they don't exist or 
#   when we don't want to reuse existing ones
if [[ ! -f key/${PRIV_KEY} || ! key/${PUB_KEY} || $reuseKey -eq 0 ]]; then
  echo
  stepCnt=$((stepCnt+1))
  rm -rf "${CUR_DIR}/key/*"
  echo "== STEP ${stepCnt} :: Create a public/private key pair =="
  $whichPulsar tokens create-key-pair \
     --output-private-key ${CUR_DIR}/key/${PRIV_KEY} \
     --output-public-key ${CUR_DIR}/key/${PUB_KEY}
fi

echo
stepCnt=$((stepCnt+1))
echo "== STEP ${stepCnt} :: Create a JWT token for each of the specificed users =="

for userName in $(echo ${tokenUserNameList} | sed "s/,/ /g"); do
  echo "   >> JWT token for user: ${userName}"
  $whichPulsar tokens create \
      --private-key  ${CUR_DIR}/key/${PRIV_KEY} \
      --subject ${userName} > ${CUR_DIR}/token/${srvHostType}s/${userName}.jwt
done

cd ../..

exit 0