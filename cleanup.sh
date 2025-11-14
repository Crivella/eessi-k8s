#!/usr/bin/env bash

BASEDIR=$(dirname "$0")
CONFIG_DIR="${BASEDIR}/config_files"

kubectl delete -f ${CONFIG_DIR}/pod-eessi.yml
kubectl delete -f ${CONFIG_DIR}/pvc-eessi.yml

helm uninstall cvmfs-csi
