#!/bin/bash
set -ex
dir=${SCRATCH_DIR:-_output}  # for writing files to bundle into secrets
image_prefix=${IMAGE_PREFIX:-sosiouxme/}
image_version=${IMAGE_VERSION:-latest}
hostname=${KIBANA_HOSTNAME:-kibana.example.com}
public_master_url=${PUBLIC_MASTER_URL:-https://kubernetes.default.svc.cluster.local:443}
# only needed for writing a kubeconfig:
master_url=${MASTER_URL:-https://kubernetes.default.svc.cluster.local:443}
master_ca=${MASTER_CA:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}
token_file=${TOKEN_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}
# other env vars used:
# PROJECT, WRITE_KUBECONFIG
# other env vars used (expect base64 encoding):
# KIBANA_KEY, KIBANA_CERT, SERVER_TLS_JSON

rm -rf $dir && mkdir -p $dir && chmod 700 $dir || :

# cp/generate CA
if [ -s /secret/ca.key ]; then
	cp {/secret,$dir}/ca.key
	cp {/secret,$dir}/ca.crt
	echo "01" > $dir/ca.serial.txt
else
    openshift admin ca create-signer-cert  \
      --key="${dir}/ca.key" \
      --cert="${dir}/ca.crt" \
      --serial="${dir}/ca.serial.txt" \
      --name="logging-signer"
fi

# generate ES proxy certs
openshift admin ca create-server-cert  \
      --key=$dir/es-proxy.key \
      --cert=$dir/es-proxy.crt \
      --hostnames=logging-es,logging-es-mutualtls \
      --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"

# use or generate Kibana proxy certs
if [ -n "${KIBANA_KEY}" ]; then
	echo "${KIBANA_KEY}" | base64 -d > $dir/kibana.key
	echo "${KIBANA_CERT}" | base64 -d > $dir/kibana.crt
elif [ -s /secret/kibana.crt ]; then
	# use files from secret if present
	cp {/secret,$dir}/kibana.key
	cp {/secret,$dir}/kibana.crt
else #fallback to creating one
    openshift admin ca create-server-cert  \
      --key=$dir/kibana.key \
      --cert=$dir/kibana.crt \
      --hostnames=kibana,${hostname} \
      --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
fi

echo 03 > $dir/ca.serial.txt  # otherwise openssl chokes on the file
echo Generating signing configuration file
cat - conf/signing.conf > $dir/signing.conf <<CONF
[ default ]
dir                     = ${dir}               # Top dir
CONF

# use or copy proxy TLS configuration file
if [ -n "${SERVER_TLS_JSON}" ]; then
	echo "${SERVER_TLS_JSON}" | base64 -d > $dir/server-tls.json
elif [ -s /secret/server-tls.json ]; then
	cp /secret/server-tls.json $dir
else
	cp conf/server-tls.json $dir
fi

# generate client certs for accessing ES
cat /dev/null > $dir/ca.db
cat /dev/null > $dir/ca.crt.srl
sh scripts/generatePEMCert.sh fluentd
sh scripts/generatePEMCert.sh kibana

# generate java store/trust for the SearchGuard plugin
sh scripts/generateJKSChain.sh es-logging-cluster

# generate proxy session
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 200 | head -n 1 > "$dir/session-secret"
# generate oauth client secret
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1 > "$dir/oauth-secret"

# set up configuration for client
if [ -n "${WRITE_KUBECONFIG}" ]; then
    # craft a kubeconfig, usually at $KUBECONFIG location
    oc config set-cluster master \
        --api-version='v1' \
	--certificate-authority="${master_ca}" \
	--server="${master_url}"
    oc config set-credentials account \
	--token="$(cat ${token_file})"
    oc config set-context current \
	--cluster=master \
	--user=account \
	--namespace="${PROJECT}"
    oc config use-context current
fi

# (re)generate secrets
echo "Deleting existing secrets"
oc delete secret logging-fluentd logging-elasticsearch logging-es-proxy logging-kibana logging-kibana-proxy || :

echo "Creating secrets"
oc secrets new logging-elasticsearch \
    key=$dir/keystore.jks truststore=$dir/truststore.jks
oc secrets new logging-es-proxy \
    server-key=$dir/es-proxy.key server-cert=$dir/es-proxy.crt \
    server-tls.json=$dir/server-tls.json mutual-ca=$dir/ca.crt
oc secrets new logging-kibana \
    ca=$dir/ca.crt \
    key=$dir/kibana.key cert=$dir/kibana.crt
oc secrets new logging-kibana-proxy \
    oauth-secret=$dir/oauth-secret \
    session-secret=$dir/session-secret \
    server-key=$dir/kibana.key \
    server-cert=$dir/kibana.crt \
    server-tls.json=$dir/server-tls.json
oc secrets new logging-fluentd \
    ca=$dir/ca.crt \
    key=$dir/fluentd.key cert=$dir/fluentd.crt

# (re)generate objects and templates needed
echo "Creating templates"
#oc delete template --selector=provider=openshift,logging-infra=kibana
#oc delete template --selector=provider=openshift,logging-infra=fluentd
#oc delete template --selector=provider=openshift,logging-infra=elasticsearch
#oc delete template --selector=provider=openshift,logging-infra=support
oc delete template logging-kibana-template logging-fluentd-template logging-elasticsearch-template logging-support-template || :
oc create -f templates/support.yaml
oc create -f templates/es.yaml
oc create -f templates/fluentd.yaml
oc create -f templates/kibana.yaml

echo "Deleting any previous deployment and deploying all"
oc delete all --selector logging-infra=kibana
oc delete all --selector logging-infra=fluentd
oc delete all --selector logging-infra=elasticsearch
oc delete all,sa,oauthclient --selector logging-infra=support

# Enabling service accounts
oc process -f templates/support.yaml -v "OAUTH_SECRET=$(cat $dir/oauth-secret),KIBANA_HOSTNAME=${hostname}" | oc create -f -
sa="system:serviceaccount:${PROJECT:-default}:aggregated-logging-fluentd"
openshift admin policy add-cluster-role-to-user cluster-reader $sa
oc get scc/privileged -o json | python -c "import json,sys; users = json.load(sys.stdin)['users']; users.count('$sa') == 0 and users.append('$sa'); print json.dumps({'users':users})" > $dir/patch
oc patch securitycontextconstraints/privileged -p "$(cat $dir/patch)"

# Deploying components
imgs="IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version}"
oc process logging-elasticsearch-template -v "$imgs" | oc create -f -
oc process logging-fluentd-template -v "$imgs" | oc create -f -
oc process logging-kibana-template -v "$imgs,OAP_PUBLIC_MASTER_URL=${public_master_url}" | oc create -f -

echo 'Success!'
