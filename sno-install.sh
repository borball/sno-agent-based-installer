#!/bin/bash

BASEDIR="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
TEMPLATES=$BASEDIR/templates

source ${BASEDIR}/config.cfg

OCP_RELEASE=$1; shift

if [ -z "$OCP_RELEASE" ]
then
  OCP_RELEASE='stable-4.12'
fi

OCP_RELEASE_VERSION=$(curl -s https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_RELEASE}/release.txt | grep 'Version:' | awk -F ' ' '{print $2}')

echo "You are going to download OpenShift installer ${OCP_RELEASE_VERSION}"

if [ ! -f openshift-install-linux.tar.gz ]
then
  curl -L https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_RELEASE_VERSION}/openshift-install-linux.tar.gz -o $BASEDIR/openshift-install-linux.tar.gz
  tar xfz $BASEDIR/openshift-install-linux.tar.gz openshift-install
fi

CLUSTER_WORKSPACE=$CLUSTERNAME

mkdir -p $CLUSTER_WORKSPACE

export PULLSECRETJSON=$(cat $PULLSECRET |jq -c)
export SSHKEYSTRING=$(cat $SSHKEY)

envsubst < $TEMPLATES/install-config.yaml.tmpl > $CLUSTER_WORKSPACE/install-config.yaml
envsubst < $TEMPLATES/agent-config.yaml.tmpl > $CLUSTER_WORKSPACE/agent-config.yaml

mkdir -p $CLUSTER_WORKSPACE/openshift
cp $TEMPLATES/openshift/*.yaml $CLUSTER_WORKSPACE/openshift/

export CRIO=$(envsubst < $TEMPLATES/openshift/crio.conf |base64 -w0)
export K8S=$(envsubst < $TEMPLATES/openshift/kubelet.conf |base64 -w0)
envsubst < $TEMPLATES/openshift/02-master-workload-partitioning.yaml.tmpl > $CLUSTER_WORKSPACE/openshift/02-master-workload-partitioning.yaml

envsubst < $TEMPLATES/openshift/performance-profile.yaml.tmpl > $CLUSTER_WORKSPACE/openshift/performance-profile.yaml

$BASEDIR/openshift-install --dir $CLUSTER_WORKSPACE agent create image --log-level=debug

