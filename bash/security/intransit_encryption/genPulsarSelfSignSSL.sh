#! /bin/bash


#
# NOTE: this script is used for generating self signed ceritificates
#       to be used when Pulsar inTransit encryption is enabled
#
#


usage() {
   echo
   echo "Usage: genPulsarSelfSignSSL.sh [-h] [-d] -b <broker_host_list> \
                                        -c <pulsar_cluster_name> \
                                        -root_pwd <rootPasswd> \
                                        -brkr_pwd <brkrPasswd> \
                                        [-root_expr_days <rootCertExpDays>] \
                                        [-brkr_expr_days <brokre_cert_expire_days>] \
                                        [-certSubjLineStr <certificate_subject_line_string>]"
   echo "       -h   : show usage info"
   echo "       [-d] : force downloding and overwriting the local openssl.cnf file"
   echo "       -b <broker_host_list> : broker hostname or IP list string (comma separated)"
   echo "       -c <pulsar_cluster_name> : Pulsar cluster name"
   echo "       -root_pwd <rootPasswd> : the password of the self-signed root CA key"
   echo "       -brkr_pwd <brkrPasswd> : the password of the (broker) server key"
   echo "       [-root_expr_days <rootCertExpDays>] : the expiration days of the self-signed root CA certificate (default 10 years)"
   echo "       [-brkr_expr_days <brokre_cert_expire_days>] : the expiration days of the signed (broker) server certificate (default 1 year)"
   echo "       [-certSubjLineStr <certificate_subject_line_string>] : the subject line string of the certificate"
   echo
}

if [[ $# -eq 0 || $# -gt 15 ]]; then
   usage
   exit 10
fi

DFT_rootCertExpDays=3650
DFT_brkrCertExpDays=365
DFT_certSubjLineStr="/C=US/ST=TX/L=Dallas/O=mytest.com"

forceDownload=0
brokerHostListStr=""
pulsarClusterName=""
rootPasswd=""
brkrPasswd=""
rootCertExpDays=
brkrCertExpDays=
certSubjLineStr=
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -d) forceDownload=1; ;;
      -b) brokerHostListStr="$2"; shift ;;
      -c) pulsarClusterName="$2"; shift ;;
      -root_pwd) rootPasswd="$2"; shift ;;
      -brkr_pwd) brkrPasswd="$2"; shift ;;
      -root_expr_days) rootCertExpDays="$2"; shift;;
      -brkr_expr_days) brkrCertExpDays="$2"; shift;;
      -certSubjLineStr) certSubjLineStr="$2"; shift;;
      *) echo "Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

echo

if [[ "$brokerHostListStr" == ""  ]]; then
  echo "[ERROR] Broker host list string (comma separated) can't be empty" 
  exit 20
fi

if [[ "$pulsarClusterName" == ""  ]]; then
  echo "[ERROR] Pulsar cluster name can't be empty" 
  exit 30
fi

if [[ "$rootPasswd" == ""  ]]; then
  echo "[ERROR] The password of the self-signed root CA key can't be empty" 
  exit 40
fi

if [[ "$brkrPasswd" == ""  ]]; then
  echo "[ERROR] The password of the (broker) server key can't be empty" 
  exit 50
fi

re='^[0-9]+$'
if [[ "$rootCertExpDays" == "" || ! rootCertExpDays =~ $re ]]; then
  echo "[WARN] The expiration days of the self-signed root CA certificate is invalid. Use the default setting of 3650 days" 
  rootCertExpDays=$DFT_rootCertExpDays
fi

if [[ "$brkrCertExpDays" == "" || ! brkrCertExpDays =~ $re ]]; then
  echo "[WARN] The expiration days of the signed (broker) server certificate is invalid. Use the default setting of 365 days" 
  brkrCertExpDays=$DFT_brkrCertExpDays
fi

if [[ "$certSubjLineStr" == ""  ]]; then
  echo "[WARN] The subject line in the certificate is empty. Use a default string." 
  certSubjLineStr="$DFT_certSubjLineStr"
fi

mkdir -p staging
cd staging

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

# NOTE: the self signed root ca key and certificate names must be as below
ROOT_CA_KEY_NAME="ca.key.pem"
ROOT_CA_CERT_NAME="ca.cert.pem"

echo "== STEP $stepCnt :: Create a root key and a X.509 certificate for self-signing purpose =="
echo "   >> ($stepCnt.1) Generate the self-signed root CA private key file"
openssl genrsa -aes256 \
        -passout pass:${rootPasswd} \
        -out ${CA_HOME}/private/${ROOT_CA_KEY_NAME} \
        4096
chmod 400 ${CA_HOME}/private/${ROOT_CA_KEY_NAME}

echo "   >> ($stepCnt.2) Generate the self-signed root CA certificate file"
openssl req -config openssl.cnf \
        -new -x509 -sha256 \
        -extensions v3_ca \
        -key ${CA_HOME}/private/${ROOT_CA_KEY_NAME} \
        -out ${CA_HOME}/certs/${ROOT_CA_CERT_NAME} \
        -days ${rootCertExpDays} \
        -subj ${certSubjLineStr} \
        -passin pass:${rootPasswd}
chmod 444 ${CA_HOME}/certs/${ROOT_CA_CERT_NAME}


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
            -passout pass:${brkrPasswd} \
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
            -subj "${certSubjLineStr}/CN=${borkerHost}" \
            -passin pass:${brkrPasswd}

   echo
   echo "   >> ($stepCnt.4) Sign the CSR with the ROOT certificate"
   openssl ca \
            -config openssl.cnf \
            -extensions server_cert \
            -notext -md sha256 -batch \
            -days ${brkrCertExpDays} \
            -in ${BROKER_CSR_NAME} \
            -out ${BROKER_CRT_NAME} \
            -passin pass:${rootPasswd}
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