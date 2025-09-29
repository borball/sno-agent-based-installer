#!/bin/bash

basedir="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# wait for agentserviceconfig CRD is established
oc wait --for condition=established crd agentserviceconfigs.agent-install.openshift.io --timeout=180s

# apply agent-service-config.yaml
oc apply -f $basedir/agent-service-config.yaml

