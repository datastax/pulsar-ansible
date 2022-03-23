#! /bin/bash


#
# NOTE: this script is used for generating self signed ceritificates
#       to be used when Pulsar inTransit encryption is enabled
#
#


usage() {
   echo
   echo "Usage: genPulsarSelfSignSSL.sh [-h] -b <broker_host_list> [-d]"
   echo "       -h : show usage info"
   echo "       -b <broker_host_list> : broker hostname or IP list string (comma separated)"
   echo "       -d : force downloding and overwriting the local openssl.cnf file"
   echo
}

if [[ $# -eq 0 || $# -gt 3 ]]; then
   usage
   exit 10
fi

brokerHostListStr=""
forceDownload=0
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -b) brokerHostListStr="$2"; shift ;;
      -d) forceDownload=1; ;;
      *) echo "Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

if [[ "$brokerHostListStr" == ""  ]]; then
  echo "Broker host list string (comma separated) can't be empty" 
  exit 20
fi

ROOT_CERT_PASSWORD=MyRootCAPass
ROOT_CERT_EXPIRE_DAYS=3650
BROKER_CERT_PASSWORD=MyBrokerCertPass
BROKER_CERT_EXPIRE_DAYS=365

COMP_ADDR="mytest.com"
CERT_SUBJ_LINE="/C=US/ST=TX/L=Dallas/O=${COMP_ADDR}"


mkdir -p my_pulsar_certs
cd my_pulsar_certs

export CA_HOME=$(pwd)

mkdir -p private certs crl newcerts brokers
chmod 700 private/
touch index.txt index.txt.attr
echo 1000 > serial

stepCnt=0

# Check if openssl.cnf file exists locally. If not, download it
if [[ ! -f "../openssl.cnf" ]]; then
   forceDownload=1
else
   cp ../openssl.cnf .
fi

if [[ $forceDownload -eq 1 ]]; then
  echo
  stepCnt=$((stepCnt+1))
  echo "== STEP $stepCnt :: Download openssl.cnf file =="
  wget https://raw.githubusercontent.com/apache/pulsar/master/site2/website/static/examples/openssl.cnf
fi

echo
stepCnt=$((stepCnt+1))
echo "== STEP $stepCnt :: Create a root key and a X.509 certificate for self-signing purpose =="
echo "   >> ($stepCnt.1) Generate the self-signed root CA private key file"
openssl genrsa -aes256 \
        -passout pass:${ROOT_CERT_PASSWORD} \
        -out ${CA_HOME}/private/ca.key.pem \
        4096
chmod 400 ${CA_HOME}/private/ca.key.pem

echo "   >> ($stepCnt.2) Generate the self-signed root CA certificate file"
openssl req -config openssl.cnf \
        -new -x509 -sha256 \
        -extensions v3_ca \
        -key ${CA_HOME}/private/ca.key.pem \
        -out ${CA_HOME}/certs/ca.cert.pem \
        -days ${ROOT_CERT_EXPIRE_DAYS} \
        -subj ${CERT_SUBJ_LINE} \
        -passin pass:${ROOT_CERT_PASSWORD}
chmod 444 ${CA_HOME}/certs/ca.cert.pem


echo
stepCnt=$((stepCnt+1))
echo "== STEP $stepCnt :: Generate and sign the Broker Server certificate for all specified Pulsar hosts =="

for borkerHost in $(echo $brokerHostListStr | sed "s/,/ /g"); do
   echo "   [Host:  $borkerHost]"
   
   # replace '.' with '-' in the broker host name or IP
   borkerHost2=${borkerHost//./-}

   BROKER_KEY_NAME="${CA_HOME}/brokers/broker.${borkerHost2}.key.pem"
   BROKER_KEY_PK8_NAME="${CA_HOME}/brokers/broker.${borkerHost2}.key-pk8.pem"
   BROKER_CSR_NAME="${CA_HOME}/brokers/broker.${borkerHost2}.csr.pem"
   BROKER_CRT_NAME="${CA_HOME}/brokers/broker.${borkerHost2}.crt.pem"

   echo "   >> ($stepCnt.1) Generate the Server Certificate private key file"
   openssl genrsa \
            -passout pass:${BROKER_CERT_PASSWORD} \
            -out ${BROKER_KEY_NAME} \
            2048

   echo
   echo "   >> ($stepCnt.2) Convert the private key file to PKCS8 format"
   openssl pkcs8 \
            -topk8 -nocrypt \
            -inform PEM -outform PEM \
            -in ${BROKER_KEY_NAME} \
            -out ${BROKER_KEY_PK8_NAME}

   echo
   echo "   >> ($stepCnt.3) Generate the CSR file"
   openssl req \
            -config openssl.cnf \
            -new -sha256 \
            -key ${BROKER_KEY_NAME} \
            -out ${BROKER_CSR_NAME} \
            -subj "${CERT_SUBJ_LINE}/CN=${borkerHost}" \
            -passin pass:${BROKER_CERT_PASSWORD}

   echo
   echo "   >> ($stepCnt.4) Sign the CSR with the ROOT certificate"
   openssl ca \
            -config openssl.cnf \
            -extensions server_cert \
            -notext -md sha256 -batch \
            -days ${BROKER_CERT_EXPIRE_DAYS} \
            -in ${BROKER_CSR_NAME} \
            -out ${BROKER_CRT_NAME} \
            -passin pass:${ROOT_CERT_PASSWORD}
   echo
   echo
done

cd ..

exit 0


## Old code for reading broker host list from an external file
# ------------
# brokerListFileFullPath="$(cd $(dirname $brokerListFile); pwd)/$(basename $brokerListFile)"
# while IFS= read -r line
# do
# done < "$brokerListFileFullPath"