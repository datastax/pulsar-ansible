#! /bin/bash

usage() {
   echo
   echo "Usage: cleanupPulsarSelfSignSSL.sh [-h] -host_type <srv_host_type> "
   echo "       -h   : show usage info"
   echo "       -host_type <srv_host_type>: Pulsar server host type that needs to clean up TLS certificates (e.g. broker, functions_worker)"
   echo
}

if [[ $# -eq 0 || $# -gt 2 ]]; then
   usage
   exit 10
fi

srvHostType=""
while [[ "$#" -gt 0 ]]; do
   case $1 in
      -h) usage; exit 0 ;;
      -host_type) srvHostType="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; exit 20 ;;
   esac
   shift
done

rm -rf staging/index.* staging/serial* staging/newcerts/* staging/crl/* staging/certs/${srvHostType}s/*