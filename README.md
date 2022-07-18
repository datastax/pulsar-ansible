- [1. Overview](#1-overview)
- [2. Executing Ansible Playbooks](#2-executing-ansible-playbooks)
  - [2.1. Host Inventory file Structure](#21-host-inventory-file-structure)
  - [2.2. Deploy a new Pulsar Cluster](#22-deploy-a-new-pulsar-cluster)
  - [2.3. Pulsar Cluster Operation](#23-pulsar-cluster-operation)
  - [2.4. Geo-replication Deployment](#24-geo-replication-deployment)
- [3. Customize Cluster Deployment](#3-customize-cluster-deployment)
  - [3.1. Download or Copy Pulsar Release Binary](#31-download-or-copy-pulsar-release-binary)
  - [3.2. Customize Pulsar JVM Settings, Log Directory, and Data Directory](#32-customize-pulsar-jvm-settings-log-directory-and-data-directory)
  - [3.3. Functions Worker](#33-functions-worker)
  - [3.4. Rack awareness](#34-rack-awareness)
  - [3.5. Security](#35-security)
  - [3.6. Transaction Support](#36-transaction-support)
  - [3.7. Broker Ensemble Size (E), Write Quorum(Qw), and Ack Quorum(Qa)](#37-broker-ensemble-size-e-write-quorumqw-and-ack-quorumqa)
- [4. Update Cluster Configuration and Rolling Restart](#4-update-cluster-configuration-and-rolling-restart)
- [5. Update Pulsar Cluster Version (Upgrade and Downgrade)](#5-update-pulsar-cluster-version-upgrade-and-downgrade)
- [6. Debug Pulsar Cluster Issues](#6-debug-pulsar-cluster-issues)

# 1. Overview
 
The Ansible scripts in this GitHub repo are used to deploy a single Apache Pulsar cluster using DataStax **Luna Streaming**, **VM (non-K8s)** based [releases](https://github.com/datastax/pulsar/releases).
 
The scripts were tested with Ansible version 2.12.x and Python version 3.10.x on a Linux based machine (including Mac).
 
# 2. Executing Ansible Playbooks
 
This repo. includes a dozen of Ansible playbooks that can be categorized in several groups.
* Deploy a new Pulsar cluster, including DataStax Luna Streaming AdminConsole and HeartBeat components
* Pulsar cluster operation related
* Geo-replication deployment (**TBD**)
 
The command to run a particular playbook is as below:
```
$ ansible-playbook -i hosts.ini <playbook_name> --private-key=</path/to/ssh/key/file> -u <ssh_user_name>
```
 
## 2.1. Host Inventory file Structure
 
A template of the host inventory file, [*hosts.ini.template*](hosts.ini.template), is included in this repo. The structure of this file is straightforward. there a few things that need to pay attention to:
 
* Set the Pulsar cluster as a global variable **cluster_name**
* For each host machine, either the host IP or the DNS name can be used. But,
  * If the host IP is used, make sure the global variable, **use_dns_name**, is set to false. Otherwise, set it to true.
```
[all:vars]
cluster_name="MyCluster"
use_dns_name="false"
```
 
* In the **bookkeeper** group, the *rack_name* parameter is related with Pulsar's rack awareness placement and it determines which bookkeeper should belong to which rack.
```
[bookkeeper]
<public_bookie_ip1> private_ip=<private_bookie_ip1> rack_name=<availability_zone_1>
<public_bookie_ip2> private_ip=<private_bookie_ip2> rack_name=<availability_zone_2>
<public_bookie_ip3> private_ip=<private_bookie_ip3> rack_name=<availability_zone_3>
```
 
## 2.2. Deploy a new Pulsar Cluster
 
The following Ansible playbooks are needed to set up a new Pulsar cluster and they're recommended to start in sequence.
 
| Payblook Name | Description | NOTE |
| ------------- | ----------- | ---- |
| 01.create_secFiles.yaml | Create Pulsar security related files (e.g. JWT tokens, trusted certificates, etc.) | This is **ONLY** needed when Pulsar authentication and/or in-transit encryption is enabled |
| 02.deploy_pulsarCluster.yaml | Deploy a single Pulsar cluster | The following Pulsar server components will be installed and configured: ***zookeepers***, ***bookkeepers***, ***brokers***, and ***function workers****. It also includes properly setting Pulsar client configurations (*client.conf*) |
| 03.assign_bookieRackaware.yaml | Assign bookkeepers to racks | This is **ONLY** needed when Pulsar and bookkeeper rack awareness is enabled and there are multiple racks |
| 04.deploy_pulsarFuncWorker.yaml | Deploy dedicated function workers | This is **ONLY** needed when ***dedicated*** function workers are needed. If function workers are deployed (by *02.deploy_pulsarCluster.yaml* ) as part of the brokers. This playbook is **NOT** needed |
| 05.deploy_adminConsole.yaml | Deploy a Pulsar AdminConsole component as the web admin UI for a deployed Pulsar cluster | DataStax Luna Streaming only |
| 06.deploy_heartBeat.yaml | Deploy a Pulsar HeartBeat component that helps monitor the health of a deployed Pulsar cluster | DataStax Luna Streaming only |
 
## 2.3. Pulsar Cluster Operation
 
There are a few other Ansible playbooks that make easy of certain Pulsar cluster operations
 
| Playbook Name | Description | Note |
| ------------- | ----------- | ---- |
| update_pulsarCluster_version.yaml | Upgrade (and downgrade) Pulsar cluster version | **NOTE**: Be cautious when using this playbook, especially when the version difference is big. Currently it is only tested between Pulsar 2.8 and 2.10. |
| update_clusterConfig_restart.yaml | Update cluster configuration and restart the cluster | **NOTE**: Not all Pulsar server configuration changes are non-breaking. Some changes need to rebuild the cluster in some way. |
| shutdown_pulsarCluster.yaml | Shut down the Pulsar cluster. | This playbook has an option that allows to clean up the Pulsar cluster installation, including data directories, after the cluster is down. |
| start_pulsarCluster.yaml | Start the Pulsar cluster. | This plabook is no-op when running against a Pulsar cluster that is up and running. |
| shutdown_adminConsole.yaml | Shut down the AdminConsole component. | Similarly, this playbook also has an option that allows to clean up the AdminConsole installation. |
| start_adminConsole.yaml | Start the AdminConsole component. | This playbook is no-op when running against an AdminConsole component that is up and running. |
| collect_srvDebugFiles.yaml | Collect server files for debug purposes. | Collect Pulsar server logs (including log gz files), main configuration files, thread dump, and heap dump. |
 
## 2.4. Geo-replication Deployment
 
Geo-replication is a common request for Pulsar cluster deployment. Using the Ansible playbooks in this repo., we can set up multiple separate Pulsar clusters easily. But it takes extra steps to enable geo-replication among these clusters. When a security feature is enabled in these clusters, the manual steps needed to enablE geo-replication among these clusters are quite involved. Because of this, we also include Ansible playbooks in this repo. to help simplify and automate geo-replication setup and configuration.
 
**TBD**: this still needs to be added ...
 
# 3. Customize Cluster Deployment
 
The cluster deployment using the Ansible playbook in this repo. is highly customizable via Ansible variables, both at the cluster level (*group_vars/all*) and at the individual server component level (*group_vars/<component_type>/all*).
 
It is not feasible (and not necessary) to list the details of all possible customization in this document. Below simply list several important customization that the scripts can do.
 
## 3.1. Download or Copy Pulsar Release Binary
 
The script supports 2 ways of getting the Pulsar release binary to the remote host server machines
* Download directly from the internet, or
* Copy it from the Ansible controller machine
 
This behavior is controlled by the following cluster level variables (*group_vars/all*)
```
internet_download: [true|false]
local_bin_homedir: "/local/path/on/ansible/controller"
```
 
## 3.2. Customize Pulsar JVM Settings, Log Directory, and Data Directory
 
The default Pulsar settings for Pulsar server JVM, including GC log directory, Pulsar server log directory, and Pulsar server data directories, are likely not suitable for production deployment. The scripts allow whether to use customized settings for each of the Pulsar server components: zookeepers, bookkeepers, and brokers.
 
This behavior is controlled first by global level variables (*group_vars/all*)
```
customize_jvm: true
customize_logdir: true
customize_gc_logdir: true
customize_datadir: true
```
 
Once the above settings are true, the server component specific settings are controlled by component level variables. For example, the following settings control the customized settings for bookkeepers (*group_vars/bookkeeper/all*)
```
pulsar_mem_bookie: "-Xms4g -Xmx4g -XX:MaxDirectMemorySize=4g"
bookie_jvm_options: >
 {% if customize_jvm is defined and customize_jvm|bool %}PULSAR_MEM="{{ pulsar_mem_bookie }}" {% endif %}
 PULSAR_EXTRA_OPTS="-XX:+PerfDisableSharedMem"
 PULSAR_GC_LOG=" "
 PULSAR_GC="-Xlog:gc:{{ tgt_pulsar_gc_log_homedir }}/pulsar_gc_%p.log:time,uptime:filecount=10,filesize=20M"
 PULSAR_LOG_DIR="{{ tgt_pulsar_log_homedir }}/bookkeeper"
 
cust_bookie_jorunal_data_homedirs:
 - /var/lib/pulsar/bookie/journal/data1
 - /var/lib/pulsar/bookie/journal/data2
cust_bookie_ledger_data_homedirs:
 - /var/lib/pulsar/bookie/ledger/data1
 - /var/lib/pulsar/bookie/ledger/data2
```
 
## 3.3. Functions Worker
 
The scripts supports several ways of deploying Pulsar functions worker
* Do not deploy functions workers at all
* Deploy functions workers as part of brokers
* Deploy functions workers on dedicated host machines
 
This behavior is controlled by the following cluster level variable:
```
# Possible values: "none", "shared", and "dedicated"
deploy_functions_worker: "none"
```
 
## 3.4. Rack awareness
 
When bookkeeper host machines are distributed among several availability zones, it is recommended to enable Pulsar rack awareness setup.
 
The scripts supports this via the following cluster level variables:
```
config_rackAwareness: true
enforceMinNumRackPerWQ: false   # default false
# NOTE: this HAS to be bigger than the available rack count.
#       otherwise, creating topic will always fail
minNumRackPerWQ: 2  
```
 
## 3.5. Security
 
The scripts also support whether to enable the following Pulsar built-in security features:
 
* JWT token based authentication
* Pulsar built-in authorization
* Client-to-broker and broker-to-broker in-transit communication TLS encryption
 
There are a set of cluster level variables to control the security related behaviors, such as the certificate expiration days, Pulsar cluster admin JWT token names, and etc.
 
```
# - Whether or not to enable Pulsar JWT authentication and authorization
enable_brkr_authNZ: true
# - Whether or not to enable Pulsar In-Transit TLS encryption
enable_brkr_tls: true
... a lot more ...
```
 
Please **NOTE** that
1) The certificates generated by the scripts in this script are using ***self-signed*** root CAs. This is usually not the case for production deployment. For real production deployment within an enterprise, the way of generating Pulsar JWT tokens and/or TLS certificates needs to follow the actual security management procedure and/or policy.
 
2) The script currently only supports enabling security features for Pulsar brokers and functions workers. The support for enabling security features for the other Pulsar server components, zookeepers and bookkeepers, is still NOT in place yet.
 
## 3.6. Transaction Support
 
Pulsar transaction support has been introduced since version 2.7, but it is not ready for production usage until version 2.10. Therefore, depending on the Pulsar version to be deployed, the scripts can control whether a Pulsar transaction is enabled.
 
This behavior is controlled by the following broker level variable (*group_vars/broker/all*)
 
```
enable_transaction: true
```
 
## 3.7. Broker Ensemble Size (E), Write Quorum(Qw), and Ack Quorum(Qa)
 
The broker setting of E/Qw/Qa is critical for message write and read performance.
 
By default, for a Pulsar cluster with more than 3 bookkeeper nodes, the E/Qw/Qa setting is following the rules as below
* E = bookkeeper_node_count - (bookeeper_node_count / bookkeeper_rack_count)
* Qw = 3
* Qa = 2
 
For a Pulsar cluster with 3 bookkeeper nodes, the E/Qw/Qa setting is 3/2/2.
 
However, the scripts allow explicit setting of E/Qw/Qa without following the above rules. This is controlled via the following broker level variables:
 
```
force_message_rf_setting: true
cust_ensemble_size: 3
cust_write_quorum: 3
cust_ack_quorum: 2
```
 
# 4. Update Cluster Configuration and Rolling Restart
 
Once a Pulsar cluster is deployed, up and running, it may sometimes require adjusting some configuration parameters (e.g. based on performance testing results). For most cases, the parameter adjustment is non-breaking (which means we don't need to rebuild a server component). If this is the case, the playbook of **update_clusterConfig_restart.yaml**, helps to avoid the manual operation overhead to make the changes and restart the Pulsar cluster. For a large cluster, such manual operation overhead can be large.
 
Please **NOTE** that this playbook supports two extra variables that you can specify from the command line, via the **--extra-vars** option.
 
```
$ ansible-playbook -i hosts.ini update_clusterConfig_restart.yaml --extra-vars="rolling_restart_only=false restart_component=<component_name>" --private-key=</path/to/ssh/key/file> -u <ssh_user_name>
```
 
* ***rolling_restart_only*** variable:
 * Can be 'true' or 'false'.
 * If set to *true*, this playbook only does rolling restart of the Pulsar cluster, without making any configuration changes. Otherwise, it will make corresponding configuration changes first before doing the rolling restart.
* ***restart_component***:
 * Can be 'zookeeper', 'bookie', 'broker', or 'functions_worker'.
 * If not set, this playbook will do a rolling restart of the entire Pulsar cluster, covering all server component types. Otherwise, it will only do rolling restart of the server hosts of the specified Pulsar component type.
 
Please **NOTE** that some configuration changes are breaking. For example, changing zookeeper data directory or bookkeeper ledger/journal directories is breaking changes. For such changes, it won't work by simply making the changes and doing rolling restarts. It normally requires rebuilding the server host that makes the changes.
 
# 5. Update Pulsar Cluster Version (Upgrade and Downgrade)
 
Please **NOTE** that
1) The version change includes both version upgrade and version downgrade, as long as the versions are compatible
2) Version change of a Pulsar cluster can be dangerous. Please **ALWAYS** fully test the procedure in a lower environment before applying in production.
3) At the moment, the version update procedure is **ONLY** tested between version 2.8.x and 2.10.x.
4) When a newer version is available (e.g. 2.11), if there are configuration parameter changes, we need to revisit the scripts and make sure the parameter changes won't break the cluster deployment.
 
The playbook, **update_pulsarCluster_version.yaml**, is used to automate the version update procedure. One thing to pay attention is:
 
* When running this playbook, the following cluster level variables (*group_vars/all*) defines the **target** cluster version. The **current** cluster version will be automatically detected by the scripts.
* If the target version is the same as the current version, this playbook will skip the execution.
 ```
pulsarLS_ver_main: "2.10"
pulsarLS_ver_secondary: "0.6"
pulsarLS_ver_signifant: "{{ pulsarLS_ver_main.split('.')[0] }}.{{ pulsarLS_ver_main.split('.')[1] }}"
pulsarLS_ver: "{{ pulsarLS_ver_main }}.{{ pulsarLS_ver_secondary }}"
```

# 6. Debug Pulsar Cluster Issues

Sometimes when we need to debug message publishing/consuming related issues in the deployed Pulsar cluster, it is very help to collect a set of information on each of the Pulsar server hosts, as below
1) The server log file (current or historical)
2) The main server configuration file, e.g. zookeeper.conf, bookkeeper.conf, broker.conf
3) The thread dump of the server process
4) The heap dump of the server process

The playbook, **collect_srvDebugFiles.yaml**, is used to automate the information collection procedure. By default, this playbook collect information items 1), 2), and 3). Item 4) (heap dump) is a heavy weight process and must be explicitly enabled. The playbook uses the following extra vars to control the information collection behavior

* **file_types**: this can be not specified, or a combination of the following values (comma seperated)
  * 'all', 'log', 'cfg', 'thrdump', 'heapdump'
  * when not specified, this is equivalent to the following combination: *file_types=log,cfg,thrdump*
* **loggz_ptn**: this is only relevant with collecting historical log file that are already archived (*.log.gz)
  * the value of this variable is a string pattern to match the log archive file name
    * E.g. *loggz_ptn=07-16* will match the log archive with name having '07-16' in it (aka, log of July 16)