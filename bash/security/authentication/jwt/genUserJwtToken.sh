#! /bin/bash


#
# NOTE: this script is used for createing a JWT token that is used
#       for Pulsar user authentication
#
#


# Check if "pulsar" executable is available
whichPulsar=$(which pulsar)
if [[ "$whichPulsar" == "" || "$whichPulsar" == *"not found"* ]]; then
  echo "Can't find \"pulsar\" executable which is necessary to create JWT tokens"
  exit 10
fi

usage() {
   echo
   echo "Usage: genUserJwtToken.sh [-h] -u <pulsar_user_name_list> -c <pulsar_cluster_name> [-r]"
   echo "       -h : show usage info"
   echo "       -u <pulsar_user_name> : Pulsar user name list (comma separated)"
   echo "       -c <pulsar_user_name> : Pulsar cluster name"
   echo "       -r : reuse existing token generation key pair if it already exists"
   echo
}

if [[ $# -eq 0 || $# -gt 5 ]]; then
   usage
   exit 20
fi

pulsarUserNameList=""
pulsarClusterName=""
reuseKey=0
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -u) pulsarUserNameList="$2"; shift ;;
      -c) pulsarClusterName="$2"; shift ;;
      -r) reuseKey=1; ;;
      *) echo "Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

if [[ "$pulsarUserNameList" == ""  ]]; then
  echo "Pulsar user name list can't be empty" 
  exit 30
fi

if [[ "$pulsarClusterName" == ""  ]]; then
  echo "Pulsar cluster name can't be empty" 
  exit 40
fi

# echo $pulsarUserNameList
# echo $pulsarClusterName

PRIV_KEY="$pulsarClusterName""_jwt_private.key"
PUB_KEY="$pulsarClusterName""_jwt_public.key"

mkdir -p my_pulsar_jwttoken
cd my_pulsar_jwttoken

mkdir -p key token

CUR_DIR=$(pwd)
stepCnt=0

# Create a public/private key pair if they don't exist or 
#   when we don't want to reuse existing ones
if [[ ! -f key/$PRIV_KEY || ! key/$PUB_KEY || $reuseKey -eq 0 ]]; then
  echo
  stepCnt=$((stepCnt+1))
  rm key/*
  echo "== STEP $stepCnt :: Create a public/private key pair =="
  $whichPulsar tokens create-key-pair \
     --output-private-key $CUR_DIR/key/$PRIV_KEY \
     --output-public-key $CUR_DIR/key/$PUB_KEY
fi

echo
stepCnt=$((stepCnt+1))
echo "== STEP $stepCnt :: Create a JWT token for each of the specificed users =="

for pulsarUserName in $(echo $pulsarUserNameList | sed "s/,/ /g"); do
  echo "   >> JWT token for user: $pulsarUserName"
  $whichPulsar tokens create \
      --private-key  $CUR_DIR/key/$PRIV_KEY \
      --subject $pulsarUserName > $CUR_DIR/token/$pulsarUserName.jwt
done

cd ..

exit 0