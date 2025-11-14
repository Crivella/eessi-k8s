#!/usr/bin/env bash

BASEDIR=$(dirname "$0")
CONFIG_DIR="${BASEDIR}/config_files"

kubectl delete -f ${CONFIG_DIR}/pod-eessi.yaml
kubectl delete -f ${CONFIG_DIR}/pvc-eessi.yaml

helm uninstall cvmfs-csi
