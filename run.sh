#!/usr/bin/env bash

if ! command -v minikube &> /dev/null
then
    echo "minikube could not be found, please install it first."
    exit 1
fi

if ! command -v helm &> /dev/null
then
    echo "helm could not be found, please install it first."
    exit 1
fi

BASEDIR=$(dirname "$0")
CONFIG_DIR="${BASEDIR}/config_files"
PREVIOUS_PROFILE=$(minikube profile)

echo "Previous minikube profile: $PREVIOUS_PROFILE"

# Set default values for minikube resources if not provided
if [ -z "$KUBE_EESSIDEMO_CPUS" ]; then
    KUBE_EESSIDEMO_CPUS=4
fi
if [ -z "$KUBE_EESSIDEMO_MEMORY" ]; then
    KUBE_EESSIDEMO_MEMORY=2048
fi
if [ -z "$KUBE_EESSIDEMO_CLEANUP" ]; then
    KUBE_EESSIDEMO_CLEANUP=true
fi
if [ -z "$KUBE_EESSIDEMO_CLEANUP_CLUSTER" ]; then
    KUBE_EESSIDEMO_CLEANUP_CLUSTER=false
fi
if [ -z "$KUBE_EESSIDEMO_PROFILE" ]; then
    KUBE_EESSIDEMO_PROFILE="eessi-demo"
fi

function cleanup {
    if [ "$KUBE_EESSIDEMO_CLEANUP" != "true" ]; then
        echo "Skipping cleanup as KUBE_EESSIDEMO_CLEANUP is set to false."
        return
    fi
    echo "Cleaning up resources..."
    minikube kubectl -- delete -f ${CONFIG_DIR}/pod-eessi.yml
    minikube kubectl -- delete -f ${CONFIG_DIR}/pvc-eessi.yml
    helm uninstall cvmfs-csi
    if [ "$KUBE_EESSIDEMO_CLEANUP_CLUSTER" == "true" ]; then
        echo "Deleting minikube cluster..."
        minikube delete -p ${KUBE_EESSIDEMO_PROFILE}
    fi
    if [ -n "$PREVIOUS_PROFILE" ]; then
        minikube profile "$PREVIOUS_PROFILE"
    fi
}

# Trap EXIT signal to ensure cleanup is done
trap cleanup EXIT

# Check if profile already exists
if minikube profile list | grep -q "${KUBE_EESSIDEMO_PROFILE} "; then
    echo "Minikube profile '${KUBE_EESSIDEMO_PROFILE}' already exists. Reusing existing profile."
else
    echo "Starting minikube with profile '${KUBE_EESSIDEMO_PROFILE}' with ${KUBE_EESSIDEMO_CPUS} CPUs and ${KUBE_EESSIDEMO_MEMORY}MB memory..."
    minikube start -p ${KUBE_EESSIDEMO_PROFILE} --cpus=${KUBE_EESSIDEMO_CPUS} --memory=${KUBE_EESSIDEMO_MEMORY} && \
    if [ $? -ne 0 ]; then
        echo "Error: minikube failed to start."
        exit 1
    fi

fi
minikube profile ${KUBE_EESSIDEMO_PROFILE}

# Ensure the default service account is created
minikube kubectl -- wait --for=create serviceaccount default --timeout=30s
if [ $? -ne 0 ]; then
    echo "Error: Default service account was not created within the timeout period."
    exit 1
fi
sleep 1

# Install the CVMFS CSI Driver via Helm
echo "Installing CVMFS CSI Driver..."
helm install cvmfs-csi oci://registry.cern.ch/kubernetes/charts/cvmfs-csi -f ${CONFIG_DIR}/helm_values.yaml
if [ $? -ne 0 ]; then
    echo "Error: Helm installation of CVMFS CSI Driver failed."
    exit 1
fi
echo "Waiting for CVMFS CSI Driver deployment to be available..."
kubectl wait --for=condition=available deployment/cvmfs-csi-controllerplugin --timeout=60s
if [ $? -ne 0 ]; then
    echo "Error: CVMFS CSI Driver deployment did not become available within the timeout period."
    exit 1
fi
echo "----------------"

# Create the Persistent Volume Claim
echo "Creating Persistent Volume Claim..."
minikube kubectl -- apply -f ${CONFIG_DIR}/pvc-eessi.yaml
minikube kubectl -- wait --for=jsonpath='{.status.phase}'=Bound pvc/software-eessi-io-pvc --timeout=30s
if [ $? -ne 0 ]; then
    echo "Error: PVC did not reach 'Bound' state within the timeout period."
    exit 1
fi
echo "Persistent Volume Claim created and bound."
echo "----------------"
sleep 2

# Create the Pod
echo "Creating Pod..."
minikube kubectl -- apply -f ${CONFIG_DIR}/pod-eessi.yaml
# Wait for the pod to be ready before executing commands
echo "Waiting for pod to be ready..."
minikube kubectl -- wait --for=condition=Ready pod/software-eessi-io-pod --timeout=60s
if [ $? -ne 0 ]; then
    echo "Error: Pod did not reach 'Ready' state within the timeout period."
    exit 1
fi
echo "----------------"

# Install SSH for mpirun
echo "Installing git and openssh-client in the pod..."
minikube kubectl -- exec software-eessi-io-pod -- bash -c "apt update && apt install -y git openssh-client" &> /dev/null
echo "----------------"

echo "Cloning eessi-demo repository and running QuantumESPRESSO example..."
minikube kubectl -- exec software-eessi-io-pod -- bash -c "\
    git clone https://github.com/EESSI/eessi-demo.git && \
    source /cvmfs/software.eessi.io/versions/2023.06/init/bash && \
    cd eessi-demo && \
    cd QuantumESPRESSO && \
    ./run.sh \
"
echo "----------------"
