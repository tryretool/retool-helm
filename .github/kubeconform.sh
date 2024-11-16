#!/bin/bash
set -euo pipefail

KUBECONFORM_VERSION="v0.6.1"
OS=$(uname)

CHANGED_CHARTS=${CHANGED_CHARTS:-${1:-}}
if [ -n "$CHANGED_CHARTS" ];
then
  CHART_DIRS=$CHANGED_CHARTS
else
  CHART_DIRS=$(ls -d charts/*)
fi

# install kubeconform
curl --silent --show-error --fail --location --output /tmp/kubeconform.tar.gz "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-${OS}-amd64.tar.gz"
tar -xf /tmp/kubeconform.tar.gz kubeconform

# validate charts
for CHART_DIR in ${CHART_DIRS}; do
  echo "Running kubeconform for folder: '$CHART_DIR'"
  helm dep up "${CHART_DIR}"
  for VALUES_FILE in $(find "${CHART_DIR}/ci" -name '*values.yaml'); do
    helm template --kube-version "${KUBERNETES_VERSION#v}" --values "${VALUES_FILE}" "${CHART_DIR}" \
      | ./kubeconform --strict --summary --kubernetes-version "${KUBERNETES_VERSION#v}"
    for OPTION_FILE in $(find "${CHART_DIR}/ci" -name '*option.yaml'); do
      echo "== Checking values file: ${VALUES_FILE} and option file: ${OPTION_FILE}"
      helm template --kube-version "${KUBERNETES_VERSION#v}" --values "${VALUES_FILE}" --values "${OPTION_FILE}" "${CHART_DIR}" \
        | ./kubeconform --strict --summary --kubernetes-version "${KUBERNETES_VERSION#v}"
    done
  done
done
