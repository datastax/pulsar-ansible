#! /bin/bash


#
# NOTE: this script is used for generating self signed ceritificates
#       to be used when Pulsar inTransit encryption is enabled
#
#


# Check if "pulsar" executable is available
whichOpenssl=$(which openssl)
if [[ "${whichOpenssl}" == "" || "${whichOpenssl}" == *"not found"* ]]; then
  echo "Can't find \"openssl\" executable which is necessary to create TLS certificates"
  exit 10
fi

usage() {
   echo
   echo "Usage: genPulsarSelfSignSSL.sh [-h] [-d] [-r] \\"
   echo "                               -clst_name <pulsar_cluster_name> \\"
   echo "                               -host_type <srv_host_type> \\"
   echo "                               -host_list <srv_host_list> \\"
   echo "                               -ca_key_pwd <rooCaKeytPasswd> \\"
   echo "                               -srv_key_pwd <srvKeyPasswd> \\"
   echo "                               [-ca_cert_expr_days <rootCertExpDays>] \\"
   echo "                               [-srv_cert_expr_days <srvCertExpDays>] \\"
   echo "                               [-certSubjLineStr <certificate_subject_line_string>]"
   echo "       -h   : show usage info"
   echo "       [-d] : force downloding and overwriting the local openssl.cnf file"
   echo "       [-r] : reuse existing root CA key and certificate if they already exist"
   echo "       -clst_name <pulsar_cluster_name> : Pulsar cluster name"
   echo "       -host_type <srv_host_type>: Pulsar server host type that needs to set up TLS certificates (e.g. broker, functions_worker)"
   echo "       -host_list <srv_host_list> : Puslar server host name or IP list string (comma separated)"
   echo "       -ca_key_pwd <rooCaKeytPasswd> : the password of the self-signed root CA key"
   echo "       -srv_key_pwd <srvKeyPasswd> : the password of the Pulsar server key"
   echo "       [-ca_cert_expr_days <rootCertExpDays>] : the expiration days of the self-signed root CA certificate (default 10 years)"
   echo "       [-srv_cert_expr_days <srvCertExpDays> : the expiration days of the signed Pulsar server certificate (default 1 year)"
   echo "       [-certSubjLineStr <certificate_subject_line_string>] : the subject line string of the certificate"
   echo
}

if [[ $# -eq 0 || $# -gt 18 ]]; then
   usage
   exit 20
fi

DFT_rootCertExpDays=3650
DFT_srvCertExpDays=365
DFT_certSubjLineStr="/C=US/ST=TX/L=Dallas/O=mytest.com"

forceDownload=0
reuseCa=0
srvHostType=""
srvHostListStr=""
pulsarClusterName=""
caKeyPasswd=""
srvKeyPasswd=""
rootCertExpDays=
srvCertExpDays=
certSubjLineStr=
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -d) forceDownload=1; ;;
      -r) reuseCa=1; ;;
      -clst_name) pulsarClusterName="$2"; shift ;;
      -host_type) srvHostType="$2"; shift ;;
      -host_list) srvHostListStr="$2"; shift ;;
      -ca_key_pwd) caKeyPasswd="$2"; shift ;;
      -srv_key_pwd) srvKeyPasswd="$2"; shift ;;
      -ca_cert_expr_days) rootCertExpDays="$2"; shift;;
      -srv_cert_expr_days) srvCertExpDays="$2"; shift;;
      -certSubjLineStr) certSubjLineStr="$2"; shift;;
      *) echo "Unknown parameter passed: $1"; exit 30 ;;
   esac
   shift
done

echo

if [[ "${pulsarClusterName// }" == ""  ]]; then
  echo "[ERROR] Pulsar cluster name can't be empty" 
  exit 40
fi

if [[ "${srvHostType// }" == ""  ]]; then
  echo "[ERROR] Pulsar server host type can't be empty" 
  exit 50
fi

if [[ "${srvHostListStr// }" == ""  ]]; then
  echo "[ERROR] Pulsar server host list string (comma separated) can't be empty" 
  exit 60
fi

if [[ "${caKeyPasswd// }" == ""  ]]; then
  echo "[ERROR] The password of the self-signed root CA key can't be empty" 
  exit 70
fi

if [[ "${srvKeyPasswd// }" == ""  ]]; then
  echo "[ERROR] The password of the Pulsar server key can't be empty" 
  exit 80
fi

re='^[0-9]+$'
if ! [[ ${rootCertExpDays} =~ $re ]]; then
  echo "[WARN] The expiration days of the root CA certificate is not provided or is invalid. Use the default setting of 3650 days" 
  rootCertExpDays=${DFT_rootCertExpDays}
fi

if ! [[ ${srvCertExpDays} =~ $re ]]; then
  echo "[WARN] The expiration days of the Pulsar server certificate is not provided or is invalid. Use the default setting of 365 days" 
  srvCertExpDays=${DFT_srvCertExpDays}
fi

if [[ "${certSubjLineStr// }" == ""  ]]; then
  echo "[WARN] The subject line in the certificate is not provided. Use the default string." 
  certSubjLineStr="${DFT_certSubjLineStr}"
fi

mkdir -p staging
cd staging

mkdir -p private crl newcerts certs/${pulsarClusterName}/${srvHostType}s
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

if [[ ${forceDownload} -eq 1 ]]; then
  whichWget=$(which wget)
  if [[ "${whichWget}" == "" || "${whichWget}" == *"not found"* ]]; then
    echo "Can't find \"wget\" executable which is necessary to download openssl.cnf file"
    exit 90
  fi

  echo
  stepCnt=$((stepCnt+1))
  echo "== STEP ${stepCnt} :: Download openssl.cnf file =="
  $whichWget https://raw.githubusercontent.com/apache/pulsar-site/main/site2/website/static/examples/openssl.cnf
fi

export CA_HOME=$(pwd)
# NOTE: the self signed root ca key and certificate names must be as below
SRV_ROOT_CA_KEY="${srvHostType}_ca.key.pem"
SRV_ROOT_CA_CERT="${srvHostType}_ca.cert.pem"
SRV_ROOT_CA_CRL="${srvHostType}_ca.crl.pem"

cp -f openssl.cnf ${srvHostType}_openssl.cnf

sed -i '' -e "s/ca.key.pem/${SRV_ROOT_CA_KEY}/g" "${srvHostType}_openssl.cnf"
sed -i '' -e "s/ca.cert.pem/${SRV_ROOT_CA_CERT}/g" "${srvHostType}_openssl.cnf"
sed -i '' -e "s/ca.crl.pem/${SRV_ROOT_CA_CRL}/g" "${srvHostType}_openssl.cnf"

if ! [[ -f private/${SRV_ROOT_CA_KEY} && -f certs/${SRV_ROOT_CA_CERT} && $reuseCa -eq 1 ]]; then
  echo
  stepCnt=$((stepCnt+1))
  echo "== STEP ${stepCnt} :: Create a root key and a X.509 certificate for self-signing purpose =="
  echo "   >> (${stepCnt}.1) Generate the self-signed root CA private key file"
  $whichOpenssl genrsa -aes256 \
          -passout pass:${caKeyPasswd} \
          -out ${CA_HOME}/private/${SRV_ROOT_CA_KEY} \
          4096
  chmod 400 ${CA_HOME}/private/${SRV_ROOT_CA_KEY}

  echo "   >> (${stepCnt}.2) Generate the self-signed root CA certificate file"
  $whichOpenssl req -config ${srvHostType}_openssl.cnf \
          -new -x509 -sha256 \
          -extensions v3_ca \
          -key ${CA_HOME}/private/${SRV_ROOT_CA_KEY} \
          -out ${CA_HOME}/certs/${SRV_ROOT_CA_CERT}  \
          -days ${rootCertExpDays} \
          -subj ${certSubjLineStr} \
          -passin pass:${caKeyPasswd}
  chmod 444 ${CA_HOME}/certs/${SRV_ROOT_CA_CERT}
fi

echo
stepCnt=$((stepCnt+1))
echo "== STEP ${stepCnt} :: Generate and sign the Pulsar server Server certificate for all specified Pulsar hosts =="

for srvHost in $(echo $srvHostListStr | sed "s/,/ /g"); do
   echo "   [Host:  $srvHost]"
   
   # replace '.' with '-' in the Pulsar server host name or IP
   srvHost2=${srvHost//./-}

   PULSAR_SRV_KEY_NAME="${CA_HOME}/certs/${pulsarClusterName}/${srvHostType}s/${srvHostType}.${srvHost2}.key.pem"
   PULSAR_SRV_KEY_PK8_NAME="${CA_HOME}/certs/${pulsarClusterName}/${srvHostType}s/${srvHostType}.${srvHost2}.key-pk8.pem"
   PULSAR_SRV_CSR_NAME="${CA_HOME}/certs/${pulsarClusterName}/${srvHostType}s/${srvHostType}.${srvHost2}.csr.pem"
   PULSAR_SRV_CRT_NAME="${CA_HOME}/certs/${pulsarClusterName}/${srvHostType}s/${srvHostType}.${srvHost2}.crt.pem"

   echo "   >> (${stepCnt}.1) Generate the PulsarServer Certificate private key file"
   $whichOpenssl genrsa \
            -passout pass:${srvKeyPasswd} \
            -out ${PULSAR_SRV_KEY_NAME} \
            2048

   echo
   echo "   >> (${stepCnt}.2) Convert the private key file to PKCS8 format"
   $whichOpenssl pkcs8 \
            -topk8 -nocrypt \
            -inform PEM -outform PEM \
            -in ${PULSAR_SRV_KEY_NAME} \
            -out ${PULSAR_SRV_KEY_PK8_NAME}

   echo
   echo "   >> (${stepCnt}.3) Generate the CSR file"
   $whichOpenssl req \
            -config ${srvHostType}_openssl.cnf \
            -new -sha256 \
            -key ${PULSAR_SRV_KEY_NAME} \
            -out ${PULSAR_SRV_CSR_NAME} \
            -subj "${certSubjLineStr}/CN=${srvHost}" \
            -passin pass:${srvKeyPasswd}

   echo
   echo "   >> (${stepCnt}.4) Sign the CSR with the ROOT certificate"
   $whichOpenssl ca \
            -config ${srvHostType}_openssl.cnf \
            -extensions server_cert \
            -notext -md sha256 -batch \
            -days ${srvCertExpDays} \
            -in ${PULSAR_SRV_CSR_NAME} \
            -out ${PULSAR_SRV_CRT_NAME} \
            -passin pass:${caKeyPasswd}
   echo
   echo
done

cd ..

exit 0


## Old code for reading Puslar server host list from an external file
# ------------
# srvListFileFullPath="$(cd $(dirname $srvListFile); pwd)/$(basename $srvListFile)"
# while IFS= read -r line
# do
# done < "$srvListFileFullPath"
