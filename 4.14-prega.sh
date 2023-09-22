#!/bin/bash


usage(){
  echo "This script will enable OCP 4.14 preGA operators located in quay.io/prega."
  echo "Reach to Red Hat team if you don't have a pull secret yet to pull operators/images from quay.io/prega."
  echo "Then update the pull-secret with command 'oc edit secret -n openshift-config pull-secret'."
  echo
}

confirm(){
  read -r -p "Have you updated the pull-secret on the cluster? Y|N?" choice
  case "$choice" in
    y|Y ) echo "yes";;
    n|N ) echo "no";;
    * ) echo "invalid";;
  esac
}

disable_default_catalog_sources(){
  echo "Disable default catalogsources:"
  cat << EOF > patchoperatorhub.yaml
- op: add
  path: /spec/sources
  value:
  - disabled: true
    name: redhat-marketplace
  - disabled: true
    name: community-operators
  - disabled: true
    name: redhat-operators
  - disabled: true
    name: certified-operators
EOF

  oc patch operatorhub cluster --type json -p "$(cat patchoperatorhub.yaml)"
  echo
}

enable_prega_catalog_source(){
  echo "Enable prega catalogsource:"
  oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
 name: redhat-operators
 namespace: openshift-marketplace
spec:
 displayName: Red Hat Operators
 image: quay.io/prega/redhat-operator-index:v4.14
 publisher: Red Hat
 sourceType: grpc
EOF

echo

oc apply -f - <<EOF
---
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  labels:
    operators.openshift.org/catalog: "true"
  name: prega
spec:
  repositoryDigestMirrors:
    - mirrors:
      - quay.io/prega/test/rh-osbs
      source: registry-proxy.engineering.redhat.com/rh-osbs
    - mirrors:
      - quay.io/prega/test/openshift4
      source: registry.redhat.io/openshift4
EOF
echo
}

how_to_install_operators(){
  echo
  echo "Next you can install the operators with command 'oc apply -f templates/openshift/day1/<operator>', for example: "
  echo
  echo "    oc apply -f templates/openshift/day1/ptp"
  echo
  echo "Monitor the operator installation progress:"
  echo
  echo "    oc get subs,csv,ip -n openshift-ptp "
  echo
}

usage

if [ "yes" = $(confirm) ]; then
  disable_default_catalog_sources
  enable_prega_catalog_source
  how_to_install_operators
else
  echo
  echo "Rerun the script when you are ready."
fi
