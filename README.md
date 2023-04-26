# ECK stack Setup on Kubernetes

This directory includes all scripts needed for setting up a working ECK inside a Kubernetes cluster.

## Prerequisites

[Kubernetes](https://kubernetes.io/docs/setup/)

[kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)

[yq](https://github.com/mikefarah/yq)

## Run
```bash
./eck-deployer.sh <k8s-namespace> elastic-cluster.yaml kibana-agent.yaml beat-agent.yaml
```

## Legend

[elastic-cluster](./elastic-cluster.yaml), k8s manifest for a single `elasticsearch` CRD.

[kibana-agent](./kibana-agent.yaml),k8s manifest for a single `kibana` CRD.

[beat-agent](./beat-agent.yaml), k8s manifest for a single `beat` CRD.

