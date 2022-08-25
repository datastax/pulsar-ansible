#! /bin/bash

ansiCmd="ansible-playbook $@ -i hosts.ini.ip --private-key ~/.ssh/id_rsa_ymtest -u automaton -v"

# echo "$ansiCmd"
eval ${ansiCmd}