#!/usr/bin/env bash
set -o errexit
set -o nounset
#set -o xtrace

source config

if [ ! -x "$(command -v kubectl)" ]; then
    echo >&2 "You must have kubectl installed to use this script."
    exit 1
fi

if [ ! -x "$(command -v yq)" ]; then
    echo >&2 "You must have yq (https://github.com/mikefarah/yq) installed to use this script."
    exit 1
fi

function usage() {
    echo >&2 "Usage: $0 <K8s-namespace> <elastic-cluster-manifest> <kibana-agent-manifest> <beat-agent-manifest>"
}

if [ $# -ne 4 ]; then
    usage
    exit 1
fi

K8S_NAMESPACE="${1}"
ELASTIC_CLUSTER_MANIFEST="${2}"
KIBANA_AGENT_MANIFEST="${3}"
BEAT_AGENT_MANIFEST="${4}"

function install-eck() {
    install-eck-crds-and-operator
    install-elastic-cluster
    install-kibana-agent
    install-beat-agent
    print-kibana-connection-info
    printf "\nDone!\n"
}

function install-eck-crds-and-operator() {
    # Default namespace from the ECK operator deployment descriptors is `elastic-system`
    DEFAULT_ECK_OPERATOR_NAMESPACE="elastic-system"
    ECK_CRDS_DESCRIPTOR="https://download.elastic.co/downloads/eck/${ECK_VERSION}/crds.yaml"
    ECK_OPERATOR_DESCRIPTOR="https://download.elastic.co/downloads/eck/${ECK_VERSION}/operator.yaml"

    printf "\nInstalling ECK custom resource definitions...\n\n"
    kubectl delete --wait=true --ignore-not-found=true -f "${ECK_CRDS_DESCRIPTOR}"
    kubectl create -f "${ECK_CRDS_DESCRIPTOR}"
    printf "\n"
    kubectl --namespace "${DEFAULT_ECK_OPERATOR_NAMESPACE}" delete --wait=true --ignore-not-found=true -f "${ECK_OPERATOR_DESCRIPTOR}"
    kubectl --namespace "${DEFAULT_ECK_OPERATOR_NAMESPACE}" wait pod -l control-plane=elastic-operator --for=delete --timeout=300s
    kubectl --namespace "${DEFAULT_ECK_OPERATOR_NAMESPACE}" create -f "${ECK_OPERATOR_DESCRIPTOR}"
    kubectl -n "${DEFAULT_ECK_OPERATOR_NAMESPACE}" wait --for=condition=Ready --timeout=300s pod -l control-plane=elastic-operator
    printf "\nECK operator deployed successfully!\n"
}

function install-elastic-cluster() {
    printf "\nInstalling Elastic cluster...\n\n"
    # Bump elastic cluster version
    yq e '.spec.version = "'"${ELASTIC_CLUSTER_VERSION}"'"' -i "${ELASTIC_CLUSTER_MANIFEST}"
    ELASTIC_CLUSTER_NAME=$(yq e '.metadata.name' "${ELASTIC_CLUSTER_MANIFEST}")
    ELASTIC_CLUSTER_LABEL=$(yq e '.spec.nodeSets[0].podTemplate.metadata.labels.app' "${ELASTIC_CLUSTER_MANIFEST}")

    create-namespace "${K8S_NAMESPACE}" "${ELASTIC_CLUSTER_MANIFEST}"

    # Waiting pod associated with CRD defined in $ELASTIC_CLUSTER_MANIFEST to be deleted
    kubectl --namespace "${K8S_NAMESPACE}" wait pod -l app="${ELASTIC_CLUSTER_LABEL}" --for=delete --timeout=300s

    kubectl --namespace "${K8S_NAMESPACE}" create -f "${ELASTIC_CLUSTER_MANIFEST}"
    printf "\n"
    kubectl --namespace "${K8S_NAMESPACE}" wait elasticsearch "${ELASTIC_CLUSTER_NAME}" --for=jsonpath='{.metadata.name}'="${ELASTIC_CLUSTER_NAME}" --timeout=400s

    while ! kubectl -n "${K8S_NAMESPACE}" get secret "${ELASTIC_CLUSTER_NAME}"-es-elastic-user ; do echo "Waiting "${ELASTIC_CLUSTER_NAME}"-es-elastic-user secret to be created..."; sleep 3; done
    while [[ $(kubectl --namespace "${K8S_NAMESPACE}" get pods -l app="${ELASTIC_CLUSTER_LABEL}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "Waiting for elasticsearch pod to be Ready..." && sleep 3; done
    kubectl --namespace "${K8S_NAMESPACE}" wait pod -l app="${ELASTIC_CLUSTER_LABEL}" --for=jsonpath='{.status.phase}'=Running --timeout=400s
    printf "\nElastic cluster deployed successfully!\n"
}

function install-kibana-agent() {
    printf "\nInstalling Kibana agent...\n\n"
    # Bump kibana agent version
    yq e '.spec.version = "'"${KIBANA_AGENT_VERSION}"'"' -i "${KIBANA_AGENT_MANIFEST}"
    KIBANA_AGENT_NAME=$(yq e '.metadata.name' "${KIBANA_AGENT_MANIFEST}")
    KIBANA_AGENT_LABEL=$(yq e '.spec.podTemplate.metadata.labels.app' "${KIBANA_AGENT_MANIFEST}")
    create-namespace "${K8S_NAMESPACE}" "${KIBANA_AGENT_MANIFEST}"

    # Waiting pod associated with CRD defined in $KIBANA_AGENT_MANIFEST to be deleted
    kubectl --namespace "${K8S_NAMESPACE}" wait pod -l app="${KIBANA_AGENT_LABEL}" --for=delete --timeout=300s

    kubectl --namespace "${K8S_NAMESPACE}" create -f "${KIBANA_AGENT_MANIFEST}"
    printf "\n"
    kubectl --namespace "${K8S_NAMESPACE}" wait kibana "${KIBANA_AGENT_NAME}" --for=jsonpath='{.metadata.name}'="${KIBANA_AGENT_NAME}" --timeout=400s

    while [[ $(kubectl --namespace "${K8S_NAMESPACE}" get pods -l app="${KIBANA_AGENT_LABEL}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "Waiting for kibana pod to be Ready..." && sleep 5; done
    kubectl --namespace "${K8S_NAMESPACE}" wait pod -l app="${KIBANA_AGENT_LABEL}" --for=jsonpath='{.status.phase}'=Running --timeout=400s
    printf "\nKibana agent deployed successfully!\n"
}

function install-beat-agent() {
    printf "\nInstalling Beat agent...\n\n"
    # Bump Beat agent version
    yq e '.spec.version = "'"${BEAT_AGENT_VERSION}"'"' -i "${BEAT_AGENT_MANIFEST}"
    yq e '.spec.version = "'"${BEAT_AGENT_VERSION}"'"' -i "${BEAT_AGENT_MANIFEST}"

    BEAT_AGENT_NAME=$(yq e '.metadata.name' "${BEAT_AGENT_MANIFEST}")
    BEAT_AGENT_LABEL=$(yq e '.spec.daemonSet.podTemplate.metadata.labels.app' "${BEAT_AGENT_MANIFEST}")

    create-namespace "${K8S_NAMESPACE}" "${BEAT_AGENT_MANIFEST}"

    # Waiting pod associated with CRD defined in $BEAT_AGENT_MANIFEST to be deleted
    kubectl --namespace "${K8S_NAMESPACE}" wait pod -l app="${BEAT_AGENT_LABEL}" --for=delete --timeout=300s

    kubectl --namespace "${K8S_NAMESPACE}" create -f "${BEAT_AGENT_MANIFEST}"
    printf "\n"
    kubectl --namespace "${K8S_NAMESPACE}" wait beat "${BEAT_AGENT_NAME}" --for=jsonpath='{.metadata.name}'="${BEAT_AGENT_NAME}" --timeout=400s

    while ! kubectl --namespace "${K8S_NAMESPACE}" get pod -l app="${BEAT_AGENT_LABEL}" ; do echo "Waiting beat pods to be created..."; sleep 3; done
    kubectl --namespace "${K8S_NAMESPACE}" wait pod -l app="${BEAT_AGENT_LABEL}" --for=jsonpath='{.status.phase}'=Running --timeout=400s
    printf "\nBeat agent deployed successfully!\n"
}

function create-namespace() {
    # Create namespace iff does not exist or delete the resources specified inside the manifest file
    if [ "$(kubectl get ns | grep "${1}" | cut -d ' ' -f1)" == "${1}" ]; then
        printf "K8s namespace [%s] already exists! \n\n" "$1"
        printf "Deleting K8s resources specified in [%s] manifest... \n" "${2}"

        kubectl --namespace "${1}" delete --wait=true --ignore-not-found=true -f "${2}"
        printf "\n"
    else
        echo "Creating K8s namespace [${1}]..."
        kubectl create namespace "${1}"
    fi
}

function print-kibana-connection-info() {
   NODE_IP=$(kubectl get nodes --selector=kubernetes.io/role!=master -o jsonpath={.items[0].status.addresses[?\(@.type==\"InternalIP\"\)].address})
   ELASTICSEARCH_NAME=$(yq e '.metadata.name' "${ELASTIC_CLUSTER_MANIFEST}")
   KIBANA_PASSWORD=$(kubectl -n "${K8S_NAMESPACE}" get secret "${ELASTICSEARCH_NAME}"-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo)

   printf "Access Kibana UI through [https://%s:5601]\n\n" "${NODE_IP}"
   printf "Username: elastic\n"
   printf "Password: %s\n" "${KIBANA_PASSWORD}"
}

install-eck