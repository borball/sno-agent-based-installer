#!/bin/bash

config_file=$1
kubeconfig=$2

oc --kubeconfig=$kubeconfig patch mcp master --type merge -p '{"spec":{"osImageStream":{"name":"rhel-10"}}}'
