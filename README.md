# Using EESSI in kubernetes with cvmfs-csi

Showcase how to access and use EESSI from within a kubernetes cluster using the [CernVM-FS Container Storage Interface (CSI) driver](https://github.com/cvmfs-contrib/cvmfs-csi).

## Requirements

- `minikube` command available (see [docs](https://minikube.sigs.k8s.io/docs/start/?arch=%2Flinux%2Fx86-64%2Fstable%2Fbinary+download) on how to install)
- `helm` command available (see [docs](https://helm.sh/docs/intro/install/) on how to install)

## Demo

### With all-in-one script

```bash
# Number of CPUs to assign to the cluster
export KUBE_EESSIDEMO_CPUS=4
# Memory in MB to assign to the cluster
export KUBE_EESSIDEMO_MEMORY=2048
# Remove everything (including minikube cluster) after the demo
export KUBE_EESSIDEMO_CLEANUP=true
# Name for the minikube cluster to create (must not already exist)
export KUBE_EESSIDEMO_PROFILE=eessi-demo

./run.sh
```

### Manually

- Start a minikube cluster

  ```bash
  minikube start --cpus=4 --memory=2048 --profile=eessi-demo
  ```

- Install the cvmfs-csi driver using helm (with the provided values file to configure EESSI access)

  ```bash
  helm install cvmfs-csi oci://registry.cern.ch/kubernetes/charts/cvmfs-csi -f config_files/helm_values.yaml
  ```

- Create a persistent volume claim to access EESSI

  ```bash
  minikube kubectl -- apply -f config_files/pvc-eessi.yaml
  ```

- Create a pod that uses the persistent volume claim

  ```bash
  minikube kubectl -- apply -f config_files/pod-eessi.yaml
  ```

- Access the pod

  ```bash
  minikube kubectl -- exec -it eessi-pod -- bash
  ```

- Run the QE demon inside the pod

  ```bash
  # Install ssh for OpenMPI and git to clone the repo
  apt update && apt install -y git openssh-client
  # Initialize EESSI
  source /cvmfs/software.eessi.io/versions/2023.06/init/bash
  # Clone the eessi-demo repository
  git clone https://github.com/EESSI/eessi-demo.git
  cd eessi-demo/QuantumESPRESSO
  # Run the QE demo
  ./run.sh
  ```