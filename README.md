- [1. Overview](#1-overview)
  - [1.1. Ansible, bash, and python version](#11-ansible-bash-and-python-version)
  - [1.2. Execute the scripts](#12-execute-the-scripts)
- [2. Cluster Topology Definition and Auto-gen of Ansible Host Inventory File](#2-cluster-topology-definition-and-auto-gen-of-ansible-host-inventory-file)
  - [2.1. Cluster Topology Raw Definition File](#21-cluster-topology-raw-definition-file)
  - [2.2. Auto-gen of Ansible Host Inventory File](#22-auto-gen-of-ansible-host-inventory-file)
- [3. Global Ansible Variables](#3-global-ansible-variables)
  - [3.1. Basic global variables](#31-basic-global-variables)
  - [3.2. Derived/Computed global variables](#32-derivedcomputed-global-variables)
    - [3.2.1. Select the right derived/computed global variables](#321-select-the-right-derivedcomputed-global-variables)
- [4. Ansible Playbooks](#4-ansible-playbooks)
  - [4.1. Server selection (derived/computed) global variable](#41-server-selection-derivedcomputed-global-variable)
  - [4.2. 00.sanityCheck.yaml](#42-00sanitycheckyaml)
  - [4.3. 01.create_secFiles.yaml](#43-01create_secfilesyaml)
  - [4.4. 02.deploy_pulsarCluster.yaml](#44-02deploy_pulsarclusteryaml)
  - [4.5. 03.assign_bookieRackaware.yaml](#45-03assign_bookierackawareyaml)
  - [4.6. 10.deploy_adminConsole.yaml](#46-10deploy_adminconsoleyaml)
  - [4.7. deploy_heartBeat.yaml](#47-deploy_heartbeatyaml)
  - [4.8. 20.update_clientSetting.yaml](#48-20update_clientsettingyaml)
  - [4.9. 21.restart_pulsarCluster_with_configChg.yaml](#49-21restart_pulsarcluster_with_configchgyaml)
  - [4.10. 22.update_pulsarCluster_version.yaml](#410-22update_pulsarcluster_versionyaml)
  - [4.11. 23.manual_autorecovery_op.yaml](#411-23manual_autorecovery_opyaml)
  - [4.12. 31.shutdown_pulsarCluster.yaml and 31.start_pulsarCluster.yaml](#412-31shutdown_pulsarclusteryaml-and-31start_pulsarclusteryaml)
  - [4.13. 32.shutdown_adminConsole.yaml and 33.start_adminConsole.yaml](#413-32shutdown_adminconsoleyaml-and-33start_adminconsoleyaml)
  - [4.14. 70.collect_srvStatus_with_kill.yaml](#414-70collect_srvstatus_with_killyaml)
  - [4.15. 71.collect_srvDebugFiles.yaml](#415-71collect_srvdebugfilesyaml)
    - [4.15.1. Local folder structure for the collected debug files](#4151-local-folder-structure-for-the-collected-debug-files)
  - [4.16. 80.decomm_Bookies.yaml](#416-80decomm_bookiesyaml)
  - [4.17. 90.buildAcl.sh](#417-90buildaclsh)
  - [4.18. 91.setup_georep.sh](#418-91setup_georepsh)
- [5. Customize Cluster Deployment](#5-customize-cluster-deployment)
  - [5.1. Download or copy Pulsar release binary](#51-download-or-copy-pulsar-release-binary)
  - [5.2. Customize Pulsar JVM settings, gclog, log directory, and data Directory](#52-customize-pulsar-jvm-settings-gclog-log-directory-and-data-directory)
  - [5.3. Functions Worker](#53-functions-worker)
  - [5.4. Autorecovery](#54-autorecovery)
  - [5.5. Bookkeeper rack awareness](#55-bookkeeper-rack-awareness)
  - [5.6. Security](#56-security)
  - [5.7. Transaction Support](#57-transaction-support)
  - [5.8. Broker Ensemble Size (E), Write Quorum(Qw), and Ack Quorum(Qa)](#58-broker-ensemble-size-e-write-quorumqw-and-ack-quorumqa)

# 1. Overview
 
The Ansible playbook scripts and bash scripts in this GitHub repo are used to automate the deployment of an Apache Pulsar cluster (as well as the automation of some key operations) in a VM (non-K8s) based environment. The Apache Pulsar to be deployed can be either the [OSS Apache release](https://pulsar.apache.org/download) or the DataStax **[Luna Streaming** release](https://github.com/datastax/pulsar/releases).
## 1.1. Ansible, bash, and python version
 
The following software version needs to be met in order to run the scripts successfully.
 
* Ansible: 2.10+ (tested with version 2.12.x and 2.13.x)
* Bash: 4.0+ (tested with GNU bash version 5.2.2)
* Python: 3.x (tested with version 3.7.10)
 
## 1.2. Execute the scripts
 
Not all **bash** scripts need to be executed manually. Some of them are called from within the Ansible playbooks automatically. But all bash scripts in this repo have a helper function to show the usage of the bash scripts, via the "-h" CLI parameter.
```
$ <bash_script> -h
```
 
The **Ansible playbook** scripts can definitely be executed directly using the following command:
```
$ ansible-playbook -i <host_inventory_file> <playbook_name> [--extra-vars "..."] --private-key=</path/to/ssh/key/file> -u <ssh_user_name>
```
 
However, since the scripts can be used to deploy multiple Pulsar clusters, different sets of SSH keys and users may be used. In order to simplify the execution of the Ansible playbooks across multiple Pulsar clusters, the following two convenience bash scripts are used:
 
1) **senenv_automation.sh**: This script defines several environment variables to be used in the next step
```
ANSI_SSH_PRIV_KEY="<ssh_private_key_file_path>"
ANSI_SSH_USER="<ssh_user_name>"
ANSI_DEBUG_LVL="[ |-v|-vv|-vvv]"
CLUSTER_NAME="<current_Pulsar_cluster_name>"
```
 
2) **run_automation.sh**: This script is used to execute a specific Ansible playbook with possible extra variables. The usage of this script is as below:
```
$ run_automation.sh -h
$ run_automation.sh <ansible_playbook_yaml_file> [--extra-vars '"var1=value1 var2=value2 ..."']
```
 
**NOTE**: if the ansible-playbook takes extra ansible variables using "--extra-vars" option, the double-quoted variables must be wrapped within a pair of single-quotes when passing into the *run_automation.sh* bash script.
 
# 2. Cluster Topology Definition and Auto-gen of Ansible Host Inventory File
 
You can use the automation scripts in this repo to deploy multiple clusters, each with its unique topology. Based on the topology, each cluster-to-be-deployed has its own Ansible host inventory file which can be automatically generated using a bash script.
 
In this automation framework, the cluster topology definition for different clusters must be organized in the following structure so the auto-gen script can pick up correctly.
 
```
cluster_topology
├── <pulsar_cluster_1_name>
│   └── clusterDefRaw
└── <pulsar_cluster_2_name>
   └── clusterDefRaw
```
 
Basically, each cluster must have a corresponding subfolder (with the name as the cluster name) under folder **cluster_topology**. Each cluster's subfolder has a text file, ***clusterDefRaw***that defines this cluster's topology.
 
## 2.1. Cluster Topology Raw Definition File
 
The topology raw definition file is a text file that has a series of lines and each line represents one server host to be deployed in the cluster. Each line is composed of several fields separated by ',' and each field defines a property of the server host. The meanings of these fields are as below:
 
```
0) internal facing server ip or hostname
1) external facing server ip or hostname
  * if empty, the same as the internal facing ip or hostname
2) server type: what purpose of this host machine in the Pulsar cluster
  in theory, one host machine can be used for multiple purposes (esp for lower environment)
  * possible values: zookeeper, bookkeeper, broker, functions_worker, autorecovery, standAloneClient, adminConsole, heartBeat
  * use '+' to specify multiple purposes (e.g. zookeeper+bookkeeper+broker)
3) region name
4) availability zone name
5) [broker only] contact point (yes/no): whether to be used as the contact point for a Pulsar client
6) host machine deployment status. Possible values:
  - (empty value/not set): node either already in the cluster or to be added
   - 'remove': remove node from the cluster
```
 
An example of a topology raw definition file for a cluster with 3 zookeepers, 3 bookkeepers, and 3 brokers is listed as below:
 
```
<zookeeper_node_ip_1>,,zookeeper,region1,az1,,
<zookeeper_node_ip_2>,,zookeeper,region1,az2,,
<zookeeper_node_ip_3>,,zookeeper,region1,az3,,
<bookkeeper_node_ip_1>,,bookkeeper,region1,az1,,
<bookkeeper_node_ip_2>,,bookkeeper,region1,az2,,
<bookkeeper_node_ip_3>,,bookkeeper,region1,az3,,
<broker_node_ip_1>,,broker,region1,az1,yes,
<broker_node_ip_2>,,broker,region1,az2,,
<broker_node_ip_3>,,broker,region1,az3,,
```
 
## 2.2. Auto-gen of Ansible Host Inventory File
 
Once the cluster topology raw definition file for a cluster is in place, we can use the following script to generate the Ansible host inventory file.
 
```
$ bash/buildAnsiHostInvFile.sh -clstrName <cluster_name> -hostDns [true|false]
```
 
**NOTE** that
 
1) The specified cluster name must match a subfolder name of the ***cluster_topology*** folder.
2) If the server IP is used in the topology raw definition file,
  1) "-hostDns" parameter must have value 'false'.
  2) Otherwise, it must have value 'true'.
 
The automatically generated host inventory file name has the following naming convention:
**hosts_<cluster_name>.ini**
 
# 3. Global Ansible Variables
 
## 3.1. Basic global variables
 
Many of the global Ansible variables are defined in Ansible **group_vars**.
* Some variables are applicable to all server components (zookeepers, brokers, etc.) and they will be defined in file **group_vars/all**.
* Other variables are only specific to a certain server component, and they will be defined in server component specific files as in **group_vars/<server_component>/all**. Below is the supported server component type
 * adminConsole
 * autorecovery
 * bookkeeper
 * broker
 * functions_worker
 * heartBeat
 * zookeeper
 
## 3.2. Derived/Computed global variables
 
There are also some global variables that need to be derived/computed from the cluster topology and/or from other basic global variables as explained in the previous section. The following Ansible *role* is used to calculate all derived/computed global variables:
**pulsar/common/pulsar_setGlobalVars**
 
For more detailed description of each derived/computed global variable, please check the comments in the above Ansible script.
 
### 3.2.1. Select the right derived/computed global variables
 
There are 3 general categories of the derived/computed global variables
1) The variables that are related with the Pulsar cluster metadata, such as Pulsar broker service list
2) The variables that are related with the Pulsar server host count, such as the server host counts per server component types
3) The variables that are related with selecting certain server hosts based on some conditions when executing a specific Ansible playbook
 
Since these categories of the derived/computed global variables are for different purposes, they don't need to be calculated all the time. Therefore, they can be calculated selectively which is controlled by a runtime variable *varList* which in turn has the following values:
* **svcList**: only cluster metadata related variables are derived/computed
* **svcCnt** : only server host count related variables are derived/computed
* **all**    : all variables are derived/computed
**NOTE**: the server host selection related variables are always derived/computed because it is used in almost all major Ansible playbooks
 
```
- hosts: <host_inventory_group>
 ... ...
 roles:
   - { role: pulsar/common/pulsar_setGlobalVars, varList: '[all|svcList|svcCnt]' }
```
 
# 4. Ansible Playbooks
 
In this section, all Ansible playbooks in this repo are briefly explained. Other than the basic and derived/computed global variables, different playbooks may also have unique runtime variables that can impact their execution behaviors. We'll also go through these runtime variables.
 
## 4.1. Server selection (derived/computed) global variable
 
The automation framework in this repo allows executing (almost) all Ansible playbooks on selected server hosts, instead of on all server hosts specified in the host inventory file. This is controlled the following global derived/computed variable:
 
**srv_select_criteria**, which is determined by the following runtime variables. When multiple runtime variables are provided, they're AND-ed together to get the final selection criteria.
* *srv_types*: the server hosts with certain types (zookeeper, bookkeeper, broker, etc.) will be selected.
 * multiple server types are possible by using a comma separated server type list
* *srvhost_ptn*: the server hosts whose names match certain patterns will be selected
* *rack_ptn*: the server hosts whose rack identifiers match certain patterns will be selected
 
```
--extra-vars "srv_types=<comma_sperated_server_type_list> srvhost_ptn=<server_host_name_pattern> rack_ptn=<rack_name_pattern>" (as a parameter of the Ansible playbook file)
or
--extra-vars '"srv_types=<comma_sperated_server_type_list> srvhost_ptn=<server_host_name_pattern> rack_ptn=<rack_name_pattern>"' (as a parameter of the 'run_automation.sh' file)
```
 
**For example**The following script collects a set of files (for debug purposes) from all bookkeepers in region1 whose name includes a substring of '10'.
```
$ run_automation.sh collect_srvDebugFiles --extra-vars '"srv_types=bookkeeper srvhost_ptn=10 rack_ptn=region1"'
```
 
There is also another server selection variable, **srv_select_criteria**, that is ONLY used in the Ansible playbook of decommissioning server hosts.
 
## 4.2. 00.sanityCheck.yaml
 
This playbook does sanity checks of a variety of things that make sure it is safe to proceed with the Pulsar cluster deployment. For example, below are some examples of the sanity checks included in this playbook
 
1) The host inventory file must have certain variables in order for the deployment to proceed successfully. This won't be an issue if the host inventory file is automatically generated based on the cluster topology raw definition file. However, if the host inventory file is manually created, it is possible that the host inventory file may miss some required variables.
2) Make sure the E/Qw/Qa setting is correct such that it must satisfy the following condition
```
bookkeeper node count >= E >= Qw >=Qa
```
3) When a dedicated autorecovery option is used, but there are no dedicated server hosts to run the autorecovery process.
 
Please **NOTE** that,
1) In case the cluster topology changes, it is recommended to always run this playbook before other playbooks.
 
## 4.3. 01.create_secFiles.yaml
 
The automation framework in this repo supports deploying a secured Pulsar cluster with the following security features:
* JWT based token authentication
* Authorization
* Client-to-broker TLS encryption
 
When the above security features are enabled, they need certain files to be prepared in advance such as the JWT token files, TLS private keys, public certificates, and etc. This playbook is used to generate these security related files locally (on the Ansible controller machine). The generated local files are located under the following directories:
* bash/security/authentication/jwt/staging
* bash/security/inransit_encryption/staging
 
Please **NOTE** that,
1) When security features are enabled, this playbook needs to be executed before running the playbook of *02.deploy_pulsarCluster.yaml* (for cluster deployment)
2) Otherwise, this playbook is NOT needed.
 
## 4.4. 02.deploy_pulsarCluster.yaml
 
This is the Main playbook to deploy a Pulsar cluster based on the pre-defined cluster topology as well as the global settings defined in the basic global variables under **group_vars**. In particular, this playbook does the following tasks
 
1) (optional) Install OpenJDK11
2) Download Pulsar release binary and extract to a specified target directory
3) Configure and start zookeeper processes
4) Initialize Pulsar cluster metadata
5) Configure and start bookkeeper processes, with bookkeeper sanity check
6) Configure and start broker processes
7) If relevant, configure and start dedicated autorecovery processes
8) If relevant, configure and start dedicated functions worker processes
 
## 4.5. 03.assign_bookieRackaware.yaml
 
When rack-awareness is enabled, this playbook is used to assign bookkeeper nodes to different racks.
 
## 4.6. 10.deploy_adminConsole.yaml
 
This playbook is used to deploy DataStax Pulsar AdminConsole [link](https://github.com/datastax/pulsar-admin-console), a graphical Web UI for a set of administrative tasks for interacting with a Pulsar cluster.
 
## 4.7. deploy_heartBeat.yaml
 
**TBD** (not complete yet).
 
This playbook is used to deploy DataStax Pulsar Heartbeat [link](https://github.com/datastax/pulsar-heartbeat), an availability and end-to-end performance tracking tool for a Pulsar cluster.
 
## 4.8. 20.update_clientSetting.yaml
 
This playbook is used to update settings on Pulsar client hosts. There are 2 client settings that you can set with this playbook
1) **client.conf** for a Pulsar client, which allows Pulsar client connecting to the cluster properly.
2) **.bash_profile** on the client host, which makes Pulsar binary as part of the PATH system environment variable.
 
**NOTE**: A runtime variable (**scope**), with the following possible values, is used to control which settings to update
* **Not Set**: all settings
* **config**: update settings in Pulsar client.conf
* **profile**: update .bash_profile
 
```
--extra-vars "scope=[config|profile]" (as a parameter of the Ansible playbook file)
or
--extra-vars '"scope=[config|profile]"' (as a parameter of the 'run_automation.sh' file)
```
 
## 4.9. 21.restart_pulsarCluster_with_configChg.yaml
 
This playbook will update Pulsar server configuration settings and do a rolling restart. However, it can also be used for rolling restart only if there is configuration change.
 
**NOTE**: This playbook has one runtime variable, **with_cfg_upd** (possible values: true or false), that controls whether Pulsar server configuration update is needed.
```
--extra-vars "with_cfg_upd=[true|false]" (as a parameter of the Ansible playbook file)
or
--extra-vars '"with_cfg_upd=[true|false]"' (as a parameter of the 'run_automation.sh' file)
```
 
If Pulsar server configuration update is needed, this playbook executes the following tasks on each server host
* Stop the server process if it is not already stopped
* Backup existing Pulsar server configuration files in a specified folder on the server host
* Re-configure Pulsar server configuration settings
* Start the server process
 
Please **NOTE** that,
1) The above process is executed on all server hosts in serial mode (to make sure at any time there is only one Pulsar server being updated). So this is a relatively slow playbook.
2) When *with_cfg_upd* is set to 'true', this playbook also re-configure *client.conf* file on all Pulsar client hosts
 
## 4.10. 22.update_pulsarCluster_version.yaml
 
This playbook supports updating (upgrading or downgrading) Pulsar versions for a deployed Pulsar cluster.
 
Please **NOTE** that,
1) Version change of a Pulsar cluster can be dangerous. Please **ALWAYS** fully test the procedure in a lower environment before applying in production. It is possible that this automation framework needs to be tweaked in order to support the newer version Pulsar release upgrade.
2) Pulsar version changes on the server hosts in the cluster always happen in serial mode as one by one.
  1) But for Pulsar client hosts, the version update can happen on multiple hosts at the same time.
When running this playbook, the following global variable (*group_vars/all*) defines the **target** cluster version. The **current** cluster version will be automatically detected by the scripts. If the target version is the same as the current version, this playbook execution will be executed
```
pulsarLS_ver_main: "2.10"
pulsarLS_ver_secondary: "2.2"
pulsarLS_ver_signifant: "{{ pulsarLS_ver_main.split('.')[0] }}.{{ pulsarLS_ver_main.split('.')[1] }}"
pulsarLS_ver: "{{ pulsarLS_ver_main }}.{{ pulsarLS_ver_secondary }}"
```
 
## 4.11. 23.manual_autorecovery_op.yaml
 
This playbook is used to manually enable or disable the autorecovery process. Generally speaking when a Pulsar cluster is in maintenance mode, it is recommended to disable autorecovery before the maintenance and enable it after.
 
## 4.12. 31.shutdown_pulsarCluster.yaml and 31.start_pulsarCluster.yaml
 
As the names suggest, these 2 playbooks are used to shut down and start the Pulsar server cluster.
 
**NOTE**: the "shutdown" playbook has a runtime variable, **purge_pulsar** (possible values: true or false), that controls whether to purge Pulsar binary and data files after the server process is shut down.
```
--extra-vars "purge_pulsar=[true|false]" (as a parameter of the Ansible playbook file)
or
--extra-vars '"purge_pulsar=[true|false]"' (as a parameter of the 'run_automation.sh' file)
```
 
Please **NOTE** that,
1) The *purge_pulsar* runtime variable is useful when it is intended to rebuild a Pulsar cluster completely.
 
## 4.13. 32.shutdown_adminConsole.yaml and 33.start_adminConsole.yaml
 
Similarly, these playbooks are used to shut down and start AdminConsole processes.
 
**NOTE**: the "shutdown" playbook has a runtime variable, **purge_adminConsole** (possible values: true or false), that controls whether to purge AdminConsole binary and data files after the server process is shut down.
```
--extra-vars "purge_adminConsole=[true|false]" (as a parameter of the Ansible playbook file)
or
--extra-vars '"purge_adminConsole=[true|false]"' (as a parameter of the 'run_automation.sh' file)
```
 
## 4.14. 70.collect_srvStatus_with_kill.yaml
 
This playbook is used to collect the current status of Pulsar servers, in particular the PID of the Pulsar server process and the owning user of the process. If needed, this playbook can also force kill the server process.
 
**NOTE**: this playbook has a runtime variable, **status_only** (possible values: true or false), that controls whether to only get the server status or kill it as well
```
--extra-vars "status_only=[true|false]" (as a parameter of the Ansible playbook file)
or
--extra-vars '"status_only=[true|false]"' (as a parameter of the 'run_automation.sh' file)
```
 
Please **NOTE** that,
1) The global derived/computed variable, ***srv_select_criteria***, will be very useful in selecting certain server hosts
 
An example of the execution of this Ansible playbook is illustrated as below:
```
ok: [IP1] => {
   "msg": "[zookeeper] srv_pid_num=21795, srv_pid_user=pulsar"
}
ok: [IP2] => {
   "msg": "[bookkeeper] srv_pid_num=21720, srv_pid_user=pulsar"
}
ok: [IP3] => {
   "msg": "[broker] srv_pid_num=23281, srv_pid_user=pulsar"
}
```
 
## 4.15. 71.collect_srvDebugFiles.yaml
 
Sometimes when there are server side issues (e.g. unexpected errors, performance degradation, etc.), it would be very helpful to collect a set of server side files for deeper analysis. This playbook is used to achieve this goal.
 
There are total 5 types of server files to collect by this playbook:
* Pulsar server main configuration file
* Pulsar server log (and/or log archive)
* Pulsar server gclog
* Pulsar server heap dump
* Pulsar server thread dump
 
**NOTE 1**: this playbook has a runtime variable, **file_types** (possible values: all|cfg|log|gclog|thrdump|heapdump), that controls whether to only get the server status or kill it as well
```
--extra-vars "file_types=[all|cfg|log|gclog|thrdump|heapdump]" (as a parameter of the Ansible playbook file)
or
--extra-vars '"file_types=[all|cfg|log|gclog|thrdump|heapdump]"' (as a parameter of the 'run_automation.sh' file)
```
 
**NOTE 2**: there is another runtime variable, **loggz_ptn**, that is ONLY relevant with collecting historical log archive files (e.g., *.log.gz). The value of this variable is a string pattern to match the log archive file name. For example,
* E.g. *loggz_ptn=07-16* will match the log archive with name having '07-16' in it (aka, log of July 16)
 
Please **NOTE** that,
1) This runtime variable supports multiple debug file types by providing a comma separated list, such as
```
"file_types=cfg,gclog,thdump"
```
2) If this runtime variable is NOT defined, it equals all debug file types except *heapdump*.
3) Since collecting heap dump of a server process is a heavyweight process, its debug file type must be explicitly specified, or use 'all' as the debug file type
 
If you only want to collect the debug files from only a limited set of Pulsar servers, you can always use the global derived/computed variable, ***srv_select_criteria***, to achieve that.
 
### 4.15.1. Local folder structure for the collected debug files
 
All the debug files that are collected from various Pulsar server hosts will be collectively put in a sub-folder under **collected_srv_files**. The sub-folder name is a date-time string that corresponds to the Ansible playbook execution time. Further down, the sub-folder structure is as below.
 
```
collected_srv_files
└── <date_time_in_ansible_iso8601_format>
   ├── config
   │   ├── bookkeeper
   │   │   └── <bookkeeper_1_ip>
   │   │   └── ...
   │   ├── broker
   │   │   └── <broker_1_ip>
   │   │   └── ...
   │   └── zookeeper
   │       └── <zookkeeper_1_ip>
   |       └── ...
   ├── gclog
   │   ├── bookkeeper
   │   │   └── ...
   │   ├── broker
   │   │   └── ...
   │   └── zookeeper
   │       └── ...
   ├── heapdump
   │   ├── bookkeeper
   │   │   └── ...
   │   ├── broker
   │   │   └── ...
   │   └── zookeeper
   │       └── ...
   ├── log
   │   ├── bookkeeper
   │   │   └── ...
   │   ├── broker
   │   │   └── ...
   │   └── zookeeper
   │       └── ...
   └── thrdump
       ├── bookkeeper
       │   └── ...
       ├── broker
       │   └── ...
       └── zookeeper
           └── ...
```
 
## 4.16. 80.decomm_Bookies.yaml
 
This playbook is used to decommission bookkeeper nodes from the Pulsar cluster. Decommissioning is a safe approach to remove a bookkeeper node from a Pulsar cluster without causing potential data and performance issues.
 
Please **NOTE** that,
 
1) Only bookkeeper nodes with ***deploy_status=remove*** (as below) in the host inventory file would be decommissioned. Otherwise, this playbook is a no-op.
```
[bookkeeper]
<bookie_ip> private_ip=<bookie_ip> region=region az=az1 rack_name=las-az1 deploy_status=remove
```
This is in turn determined by the cluster topology raw definition file, as below. *NOTE* that the last field has value of 'remove'
```
<bookie_ip>,,bookkeeper,las,az1,,remove
```
 
2) If you only want to select a certain set of bookkeepers to decommission, you can use another global derived/computed variable, ***srv_select_criteria_rmv***.
 
**TBD**: *This script only supports running the command of decommissioning a bookkeeper node from that server host on which that bookkeeper node is running. This doesn't require the command to provide a bookkeeper ID. However, it is possible to run the decommissioning command on another server host which requires providing the bookkeeper ID as the command parameter. This is a current limitation of this framework.*
 
## 4.17. 90.buildAcl.sh
 
This bash script is used to grant user access privileges to the Pulsar cluster (e.g. produce or consume messages from a topic or a namespace) based on a list of predefined access control list (ACL) requirements.
 
First, we need to define an ACL request list to be granted against a specific cluster, which is a text file named **aclDefRaw** under the following folder
```
permission_matrix/
├── <pulsar_cluster_name>
│   └── aclDefRaw
```
 
This file contains a list of lines with each line representing a particular ACL permission request to access a Pulsar cluster. Each line is composed of a set of fields that are comma separated. An example content of this file is as below:
```
reguser1,grant,namespace,public/default,produce+consume
reguser2,grant,topic,persistent://public/default/testtopic1,produce
reguser3,grant,topic,persistent://public/default/testtopic1,consume
```
 
The description of the fields is as below:
```
0) user role name
1) acl operation
  * possible values: grant, revoke
2) resource type
  * possible values: topic, namespace, ns-subscription, tp-subscription
3) resource name, e.g. namespace name, topic name, subscription name
4) acl action (only relevant when resource name is topic or namespace)
  * possible values: produce, consume, sources, sinks, functions, packages
  * can have multiple values using '+' to concatenate
```
 
Based on the above raw ACL permission request list, the bash script will translate them into a series of pulsar-admin commands which will be executed by a dependent Ansible script, **exec_AclPermControl.yaml**.
 
## 4.18. 91.setup_georep.sh
 
The bash script is used to set up the geo-replication between 2 Pulsar clusters.
 
As the first step of this script, it calls an Ansible script, **georep_getClstrClntCnf.yaml**, to get the following security files from the two Pulsar clusters
* Cluster admin JWT token file
* Public certificate file for TLS encryption
 
Using the fetched security files, the bash script calls Pulsar REST APIs to do the following tasks
1) In each of the Pulsar clusters, create a cluster metadata locally that represents the remote Pulsar cluster
2) In both Pulsar clusters, create the same set of Pulsar tenants, with the following metadata
  1) The tenant admin name is: ***<tenant_name>-admin***
  2) Allowed Pulsar cluster names: the name of the two Pulsar clusters to be geo-replication enabled
3) In both Pulsar clusters, create the same set of Pulsar namespaces, with the following metadata
  1) Replication cluster names: the name of the two Pulsar clusters to be geo-replication enabled
 
For the above 2nd and 3rd steps, if the specified tenants and/or namespaces already exist, the script can update existing tenants and/or namespace if the bash input parameter, *-forceTntNsUpdate*, has a value of 'true'
 
The script gets the tenant list and namespace list from the bash input parameter, *-tntNsList*, with the following value:
```
<tenant>/<namespace>,<tenant>/<namespace>,...
```
 
**TBD**: *This script currently ONLY supports the two Pulsar clusters that have the security features enabled: JWT token authentication, authorization, and client-to-broker TLS encryption. This is recommended for production deployment. However, for a DEV environment when two Pulsar clusters have no security features are enabled, this script may fail. (We need to improve this in the future version)*
 
# 5. Customize Cluster Deployment
The cluster deployment using this automation framework is highly customizable via Ansible variables, both at the cluster level (*group_vars/all*) and at the individual server component level (*group_vars/<component_type>/all*).
It is not feasible (and not necessary) to list the details of all possible customization in this document. Below simply list several important customization that the scripts can do.
## 5.1. Download or copy Pulsar release binary
The script supports 2 ways of getting the Pulsar release binary to the remote host machines
* Download directly from the internet, or
* Copy it from the Ansible controller machine
This behavior is controlled by the following global variables (*group_vars/all*)
```
internet_download: [true|false]
local_bin_homedir: "/local/path/on/ansible/controller"
```
 
The *local_bin_homedir* is the local folder on the Ansible controller machine (where the playbooks are executed). When the 'internet_download' option is set to false, the deployment script assumes the Pulsar binary release (of the matching version) exists locally. Otherwise, it stops the execution with an error.
## 5.2. Customize Pulsar JVM settings, gclog, log directory, and data Directory
The default Pulsar settings for Pulsar server JVM, including GC log directory, Pulsar server log directory, and Pulsar server data directories, are likely not suitable for production deployment. The scripts allow whether to use customized settings for each of the Pulsar server components: zookeepers, bookkeepers, brokers.
This behavior is controlled first by global level variables (*group_vars/all*)
```
customize_jvm: true
customize_logdir: true
customize_gc_logdir: true
customize_datadir: true
```
 
Some JVM settings, including the gclog, are common to all Pulsar components and therefore set in *group_vars/all* file as well.
 
```
prod_jvm_setting: false
common_jvm_settings: |
 PULSAR_EXTRA_OPTS="-XX:+PerfDisableSharedMem {{ component_pulsar_extra_opts | default('') }}"
 PULSAR_GC="-XX:+UseG1GC -XX:MaxGCPauseMillis=10 -XX:+HeapDumpOnOutOfMemoryError -XX:+ExitOnOutOfMemoryError {{ component_pulsar_gc | default('') }}"
 PULSAR_GC_LOG="-Xlog:gc*,safepoint:{{ tgt_pulsar_gc_log_homedir }}/pulsar_gc_%p.log:time,uptime,tags:filecount=10,filesize=20M"
```
 
Other than the generic, common settings, each server component also has its unique settings that are controlled by component level variables in *group_vars/<server_component>/all* file. For example, other than the common JVM settings as above, a broker may have its own JVM heap and direct memory size setting as below:
```
pulsar_mem_broker: "{% if prod_jvm_setting|bool %}-Xms4g -Xmx4g -XX:MaxDirectMemorySize=8g{% else %}-Xms1g -Xmx1g{% endif %}"
```
 
## 5.3. Functions Worker
The automation framework supports several ways of deploying Pulsar functions worker
* Do not deploy functions workers at all
* Deploy functions workers as part of brokers
* Deploy functions workers on dedicated host machines
This behavior is controlled by the following global variable (*group_vars/all*):
```
# Possible values: "none", "shared", and "dedicated"
deploy_functions_worker: "none"
```
 
## 5.4. Autorecovery
 
By default, Pulsar deploys autorecovery as part of the bookkeeper server process. This is not recommended for production deployment. This automation framework supports several ways of deploying autorecovery
* No autorecovery at all
* Integrated autorecovery as part of bookkeeper process
* Dedicated autorecovery process on dedicated server hosts
 
This behavior is controlled by the following global variable (*group_vars/all*):
```
# Possible values: "disabled", "integrated", "dedicated"
autorecovery_option: "dedicated"
```
## 5.5. Bookkeeper rack awareness
When bookkeeper host machines are distributed among several availability zones, it is recommended to enable Pulsar rack awareness setup.
This automation framework supports this via the following global variable (*group_vars/all*):
```
config_rackAwareness: true
enforceMinNumRackPerWQ: false   # default false
# NOTE: this HAS to be bigger than the available rack count.
#       otherwise, creating topic will always fail
minNumRackPerWQ: 2 
```
 
When bookkeeper rack awareness is enabled, Ansible playbook **03.assign_bookieRackaware.yaml** must be executed in order to assign bookkeepers to right racks.
## 5.6. Security
This automation framework supports whether to enable the following Pulsar built-in security features:
* JWT token based authentication
* Pulsar built-in authorization
* Client-to-broker and broker-to-broker in-transit communication TLS encryption
There are a set of global variable (*group_vars/all*) to control the security related behaviors, such as the certificate expiration days, Pulsar cluster admin JWT token names, etc.
```
# - Whether or not to enable Pulsar JWT authentication and authorization
enable_brkr_authNZ: true
# - Whether or not to enable Pulsar In-Transit TLS encryption
enable_brkr_tls: true
... a lot more ...
```
Please **NOTE** that,
1) The certificates generated by the scripts in this script are using ***self-signed*** root CAs. This is usually not the case for production deployment. For real production deployment within an enterprise, the way of generating Pulsar JWT tokens and/or TLS certificates needs to follow the actual security management procedure and/or policy.
2) The script currently only supports enabling security features for Pulsar brokers and functions workers. The support for enabling security features for the other Pulsar server components, zookeepers and bookkeepers, is still NOT in place yet.
## 5.7. Transaction Support
Pulsar transaction support has been introduced since version 2.7, but it is not ready for production usage until version 2.10. Therefore, depending on the Pulsar version to be deployed, the scripts can control whether a Pulsar transaction is enabled.
This behavior is controlled by the following broker level variable (*group_vars/broker/all*)
```
enable_transaction: true
```
## 5.8. Broker Ensemble Size (E), Write Quorum(Qw), and Ack Quorum(Qa)
The broker setting of E/Qw/Qa is critical for message write and read performance.
This automation framework allows explicit setting of E/Qw/Qa via global variables (*group_vars/all*), as below:
```
force_message_rf_setting: true
cust_ensemble_size: <some_value>
cust_write_quorum: <some_value>
cust_ack_quorum: <some_value>
```
 
If *force_message_rf_setting* value is set as false, the E/Qw/Qa value would be
* 4/3/2 (for total more than 3 bookkeeper nodes)
* 3/2/2 (for total 3 bookkeeper nodes)
* E=Qw=Qa=bookkeeper node count (for total less than 3 bookkeeper nodes)