#! /bin/bash

set -ex
dir=${SCRATCH_DIR:-_output}  # for writing files to bundle into secrets
project=${PROJECT:-default}
OPS_PROJECTS=("default" "openshift" "openshift-infra")
CA=$dir/admin-ca.crt
KEY=$dir/admin-key.key
CERT=$dir/admin-cert.crt

es_host=${ES_HOST:-logging-es}
es_port=${ES_PORT:-9200}
project=${PROJECT:-default}

function create_alias() {
    output=`curl -s --cacert $CA --key $KEY --cert $CERT -XPOST "https://$es_host:$es_port/_aliases" -d "{ \"actions\": [ { \"add\": { \"index\": \"${1}.*\", \"alias\": \"${1}.${2}.reference\"}} ] }"`

    echo Migration for project $1: $output
}

function create_context() {

# there's no good way for oc to filter the list of secrets; and there can be several token secrets per SA.
  # following template prints all tokens for aggregated-logging-fluentd; --sort-by will order them earliest to latest, we will use the last.
  local sa_token_secret_template='{{range .items}}{{if eq .type "kubernetes.io/service-account-token"}}{{if eq "aggregated-logging-fluentd" (index .metadata.annotations "kubernetes.io/service-account.name")}}{{.data.token}}
{{end}}{{end}}{{end}}'
  local failure="false"
  local nodes_active="false"
  local output=""

  # check that the aggregated-logging-fluentd SA exists and we can get its token
  if ! output=$(oc get secret --namespace="${project}" --sort-by=metadata.resourceVersion --template="$sa_token_secret_template" 2>&1); then
    echo "Error getting aggregated-logging-fluentd service account token; is the master running and are credentials working? Error from oc get secrets follows:"
    echo -n "$output"
    return 1
  elif [[ -z "$output" ]]; then
    echo "Could not find aggregated-logging-fluentd service account token in $namespace; does it exist?"
    return 1
  fi
  local token=$(echo -e "$output" | tail -1 | base64 -d)
  # set up a config context using the aggregated-logging-fluentd account and most recent token
  oc config set-credentials aggregated-logging-fluentd-account \
    --token="$token" >& /dev/null
  oc config set-context aggregated-logging-fluentd-context \
    --cluster=master \
    --user=aggregated-logging-fluentd-account \
    --namespace="${project}" >& /dev/null

  oc config use-context aggregated-logging-fluentd-context
}

function recreate_admin_certs(){

# note: following mess is because we want the error output from the first failure, not a pipeline
  if secret_ca=$(oc get secret/logging-elasticsearch --template='{{index .data "admin-ca"}}' 2>&1) && \
    [[ $secret_ca != "" ]] && \
    #secret_ca=$(echo -e "$secret_ca" | base64 -d | keytool -printcert -rfc 2>&1); then :
    secret_ca=$(echo -e "$secret_ca" | base64 -d 2>&1); then :
  else
    echo ---
    echo "There was an error while retrieving the EFK admin ca:"
    [ -n "$secret_ca" ] && echo -e "$secret_ca" || echo "The certificate is empty."
    return 1
  fi

  if secret_cert=$(oc get secret/logging-elasticsearch --template='{{index .data "admin-cert"}}' 2>&1) && \
    [[ $secret_cert != "" ]] && \
    #secret_cert=$(echo -e "$secret_cert" | base64 -d | keytool -printcert -rfc 2>&1); then :
    secret_cert=$(echo -e "$secret_cert" | base64 -d 2>&1); then :
  else
    echo ---
    echo "There was an error while retrieving the EFK admin certificate:"
    [ -n "$secret_cert" ] && echo -e "$secret_cert" || echo "The certificate is empty."
    return 1
  fi

  if secret_key=$(oc get secret/logging-elasticsearch --template='{{index .data "admin-key"}}' 2>&1) && \
    [[ $secret_key != "" ]] && \
    #secret_key=$(echo -e "$secret_key" | base64 -d | keytool -printcert -rfc 2>&1); then :
    secret_key=$(echo -e "$secret_key" | base64 -d 2>&1); then :
  else
    echo ---
    echo "There was an error while retrieving the EFK admin key:"
    [ -n "$secret_key" ] && echo -e "$secret_key" || echo "The certificate is empty."
    return 1
  fi

  echo -e "$secret_key" > $dir/admin-key.key
  echo -e "$secret_cert" > $dir/admin-cert.crt
  echo -e "$secret_ca" > $dir/admin-ca.crt

}

recreate_admin_certs
#create_context

PROJECTS=(`oc get project -o jsonpath='{.items[*].metadata.name}'`)
ES_PODS=$(oc get pods -l component=es | awk -e 'es ~ sel && $3 == "Running" {print $1}')
ES_POD=`echo $ES_PODS | cut -d' ' -f 1`

if [[ -z "$ES_POD" ]]; then
  echo "No Elasticsearch pods found running.  Cannot migrate."
  echo "Scale up ES prior to running with MODE=migrate"
  exit 1
fi

for index in "${PROJECTS[@]}"; do

  if [[ ! ( ${OPS_PROJECTS[@]} =~ $index ) ]]; then
    uid=$(oc get project "$index" -o jsonpath='{.metadata.uid}')
    create_alias $index $uid
  fi

done
