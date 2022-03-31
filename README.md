# Overview

The Ansible scripts in this GitHub repo are used to deploy a single Apache Pulsar cluster using DataStax **Luna Streaming**, **VM (non-K8s)** based [releases](https://github.com/datastax/pulsar/releases).

The scripts were tested with Ansible version 2.12.1 and Python version 3.10.1 on a Linux based machine (including Mac).

# Playbook Intro

The table below lists the available Ansible playbooks in this repo. Their descriptions are as below:

| Playbook Name | Description | Note |
| ------------- | ----------- | ---- |
| deploy_pulsar_cluster.yaml | Deploy a single Pulsar cluster | Server component configuration: Zookeepers Brokers, Bookies; Pulsar client configuration |
| shutdown_pulsar_cluster.yaml | Shut down the installed Pulsar cluster | If "purge_pulsar" variable is set to true, after the cluster is shut down, it is also purged by this playbook |
| start_pulsar_cluster.yaml | Start the installed Pulsar cluster if it is down |
| deploy_adminConsole.yaml | Deploy a Pulsar AdminConsole component as the web admin UI for a deployed Pulsar cluster | To be completed ... |
| deploy_heartBeat.yaml | Deploy a Pulsar HeartBeat component that helps monitor the health of a deployed Pulsar cluster | To be completed ... |

The command to run a playbook is as below:
```
$ ansible-playbook -i hosts.ini <playbook_name> --private-key=</path/to/ssh/key/file> -u <ssh_user_name>
```

A template of the host inventory file, *hosts.ini.template*, is included in this repo. When creating your own host inventory file, please remember that: 
1) Other than the actual host machine list, please follow exactly the host inventory structure as demonstrated in the template file, such as the number of the host groups, the names of the host groups, the relationships among the host groups, and etc.
2) For each host machine, please follow the format of *<public_ip_of_the_host> private_ip=<private_ip_of_the_host>* in the host inventory file. 
   1) If there is only one IP address for a host, use the same IP address for both the public and private IPs.
   2) The host DNS names can be used instead of the IP addresses.

# Pulsar Cluster Deployment

The script in this repo. (in particular *deploy_pulsar_cluster.yaml*) deploys a single Pulsar cluster with all mandatory server components: zookeepers, brokers, and bookkeepers (bookies) that can either share a common set of host machines or reside on separate dedicated host machines. 

For the case of multi-region/data center geo-replication, we can still use the script in this repo. to launch multiple standalone Pulsar clusters and then follow the simple and straightforward procedure as described [here](https://pulsar.apache.org/docs/en/administration-geo/#configure-replication) to manually configure geo-replication among these Pulsar clusters. 

The script, however, doesn't deploy a global configuration store (a global zookeeper cluster) that could be used for automatic metadata management across multiple Pulsar clusters.


# Security

The scripts in this repo. provides the options of installing a Pulsar cluster either with or without the following Pulsar built-in security features:
* JWT token based authentication, which includes
  * Generating an asymmetric public/private key pair that are unique to a specific Pulsar cluster 
  * Generating (and verifying) JWT tokens with given names using the asymmetric public/private key pair
* Pulsar built-in authorization, which includes
  * Support a list of cluster admin roles via Ansible variables 
  * Automatic creation of the JWT tokens for the specified cluster admin roles
* Client-to-broker and broker-to-broker in-transit communication TLS encryption, which includes
  * Creation of a pair of root CA key and self-signed root CA certificate
  * For each broker,
    * Create a broker specific private key and a certificate signing request (CSR)
    * Sign the CSR with the root CA and generate the signed certificate

One bash script (bash/security/authentication/jwt/genUserJwtToken.sh) is responsible for creating the required JWT token files.  It can take input parameters from the Ansible playbook such as the list of the cluster admin role names.

Another bash script (bash/security/intransit_encryption/genPulsarSelfSignSSL.sh) is responsible for creating the required TLS certificate files for all brokers. It can also take input parameters from the Ansible playbook such as the root CA and broker key password, the root CA and broker certificate expiration days, and etc.

Once the relevant JWT token files and the TLS certificate files are created, the Ansible playbook will automatically configure *broker.conf* file for every broker and *client.conf* file for every Pulsar client in order to pick up the security setting changes.

# Customize Pulsar cluster install via Global Variables

The Ansible scripts in this repo. are highly customizable through the global Ansible variables that are defined in *group_vars/all* file. Most of these variables are closely related with how the Pulsar cluster would be installed and configured. 


Some key customization categories are listed below:
* Pulsar server listening ports (default or customized)
* Pulsar server JVM settings (default or customized)
* Pulsar server log directory (default or customized)
* Pulsar zookeeper and bookkeeper data directories (default or customized)
* Message replication factor settings: Ensemble Size, Write Quorum, or Ack Quorum (default or customized)
* Whether or not Pulsar JWT token authentication and Pulsar authorization are enabled 
  * The name list of Pulsar cluster admin roles
* Whether or not Pulsar in-transit TLS encryptioin is enabled
  * The private key password 
  * The certificate expiration days