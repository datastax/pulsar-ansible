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

Note: Other than the first playbook ("deploy_pulsar_cluster.yaml"), all other playbooks must deal with a Pulsar cluster that is installed by the first playbook.

# Pulsar Clsuter Deployment

## Global Variables

## Install and Configuration

## Security

# Future Improvement
