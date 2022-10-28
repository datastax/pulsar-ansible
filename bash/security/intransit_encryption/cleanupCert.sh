###
# Copyright DataStax, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###

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