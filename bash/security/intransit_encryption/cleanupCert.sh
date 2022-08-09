#! /bin/bash

usage() {
   echo
   echo "Usage: cleanupPulsarSelfSignSSL.sh [-h] -clst_name <cluster_name> -host_type <srv_host_type> "
   echo "       -h   : show usage info"
   echo "       -clst_name <cluster_name> : Pulsar cluster name" 
   echo "       -host_type <srv_host_type>: Pulsar server host type that needs to clean up TLS certificates (e.g. broker, functions_worker)"
   echo
}

if [[ $# -eq 0 || $# -gt 4 ]]; then
   usage
   exit 10
fi

srvHostType=""
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -clst_name) pulsarClusterName="$2"; shift;;
      -host_type) srvHostType="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

if [[ "${pulsarClusterName}" == ""  ]]; then
  echo "Pulsar cluster name can't be empty" 
  exit 30
fi

if [[ "${srvHostType}" == ""  ]]; then
  echo "[ERROR] Pulsar server host type can't be empty" 
  exit 40
fi

rm -rf staging/index.* \
   staging/serial* \
   staging/newcerts/* \
   staging/crl/* \
   staging/${srvHostType}_openssl.cnf \
   staging/certs/${pulsarClusterName}/${srvHostType}s/*