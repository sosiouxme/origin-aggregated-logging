#!/bin/bash
set -ex
dir=${SCRATCH_DIR:-_output}  # for writing files to bundle into secrets
image_prefix=${IMAGE_PREFIX:-openshift/}
image_version=${IMAGE_VERSION:-latest}
hostname=${KIBANA_HOSTNAME:-kibana.example.com}
public_master_url=${PUBLIC_MASTER_URL:-https://kubernetes.default.svc.cluster.local:443}
project=${PROJECT:-default}
# only needed for writing a kubeconfig:
master_url=${MASTER_URL:-https://kubernetes.default.svc.cluster.local:443}
master_ca=${MASTER_CA:-/var/run/secrets/kubernetes.io/serviceaccount/ca.crt}
token_file=${TOKEN_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}
vol=${ES_VOLUME_CAPACITY:-1}
# other env vars used:
# WRITE_KUBECONFIG, KEEP_SUPPORT, ENABLE_OPS_CLUSTER
# other env vars used (expect base64 encoding):
# KIBANA_KEY, KIBANA_CERT, SERVER_TLS_JSON

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
	--namespace="${project}"
    oc config use-context current
fi

if [ "${KEEP_SUPPORT}" != true ]; then
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
	      --name="logging-signer-$$"
	fi

	# generate ES proxy certs
	function join { local IFS="$1"; shift; echo "$*"; }
	openshift admin ca create-server-cert  \
	      --key=$dir/es-proxy.key \
	      --cert=$dir/es-proxy.crt \
	      --hostnames="$(join , logging-es{,-ops}-mutualtls{,.${project}.svc.cluster.local})" \
	      --signer-cert="$dir/ca.crt" --signer-key="$dir/ca.key" --signer-serial="$dir/ca.serial.txt"
#	      --hostnames="logging-es-mutualtls" \

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
	# generate common node key for the SearchGuard plugin
	openssl rand 16 | openssl enc -aes-128-cbc -nosalt -out $dir/searchguard_node_key.key -pass pass:pass

	# generate proxy session
	cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 200 | head -n 1 > "$dir/session-secret"
	# generate oauth client secret
	cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1 > "$dir/oauth-secret"

	# (re)generate secrets
	echo "Deleting existing secrets"
	oc delete secret logging-fluentd logging-elasticsearch logging-es-proxy logging-kibana logging-kibana-proxy || :

	echo "Creating secrets"
	oc secrets new logging-elasticsearch \
	    key=$dir/keystore.jks truststore=$dir/truststore.jks \
	    searchguard.key=$dir/searchguard_node_key.key
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

fi # supporting infrastructure

# (re)generate templates needed
echo "Creating templates"
oc delete template --selector logging-infra=kibana
oc delete template --selector logging-infra=fluentd
oc delete template --selector logging-infra=elasticsearch
oc delete template --selector logging-infra=elasticsearch-pv
oc create -f templates/pv-nfs.yaml
oc process -f templates/es.yaml -v "VOLUME_CAPACITY=${vol}" | oc create -f -
es_host=logging-es-mutualtls.${project}.svc.cluster.local
es_ops_host=${es_host}
if [ "${ENABLE_OPS_CLUSTER}" == true ]; then
	oc process -f templates/es.yaml -v "VOLUME_CAPACITY=${vol},ES_CLUSTER_NAME=es-ops" | oc create -f -
	es_ops_host=logging-es-ops-mutualtls.${project}.svc.cluster.local
fi
oc process -f templates/fluentd.yaml -v "ES_HOST=${es_host},OPS_HOST=${es_ops_host}"| oc create -f -
oc process -f templates/kibana.yaml -v "OAP_PUBLIC_MASTER_URL=${public_master_url}" | oc create -f -

if [ "${KEEP_SUPPORT}" != true ]; then
	oc delete template --selector logging-infra=support
	oc process -f templates/support.yaml -v "OAUTH_SECRET=$(cat $dir/oauth-secret),KIBANA_HOSTNAME=${hostname},IMAGE_PREFIX=${image_prefix},IMAGE_VERSION=${image_version}" | oc create -f -
fi


set +x
echo 'Success!'
sa="system:serviceaccount:${project}:aggregated-logging-fluentd"
support_section=''
if [ "${KEEP_SUPPORT}" != true ]; then
	support_section="    oc delete all,sa,oauthclient --selector logging-infra=support

Create the supporting definitions (you must be cluster admin):

    oc process logging-support-template | oc create -f -

Enable fluentd service account - edit SCC with the following

    oc edit scc/privileged

Add one line as the user at the end:

- $sa

Give the account access to read labels from all pods:

    openshift admin policy add-cluster-role-to-user cluster-reader $sa

Finally, instantiate the logging components.
"
fi
ops_cluster_section=""
if [ "${ENABLE_OPS_CLUSTER}" == true ]; then
	ops_cluster_section="Do the same to create your ops cluster:

    oc process logging-es-ops-template | oc create -f -
"
fi

cat <<EOF

=================================

The deployer has created the secrets and templates required to deploy logging.
You should now use the templates as follows.

If you need to delete a previous deployment first, do the following:

    oc delete all --selector logging-infra=kibana
    oc delete all --selector logging-infra=fluentd
    oc delete all,pvc --selector logging-infra=elasticsearch
${support_section}
ElasticSearch:
--------------

    oc process logging-es-template | oc create -f -

You may repeat this multiple times to create multiple instances that will cluster.
${ops_cluster_section}
Each instance requires that a PersistentVolume be created for persistent
storage before it will deploy. If you have NFS volumes you would like
to use, you can create them with the supplied template:

    oc process logging-pv-template \
	    -v SIZE=50,NFS_SERVER=<addr>,NFS_PATH=/path \
	    | oc create -f -

Fluentd:
--------------

    oc process logging-fluentd-template | oc create -f -

You may scale the resulting deployment normally to the number of nodes:

    oc scale dc/logging-fluentd --replicas=3
    oc scale rc/logging-fluentd-1 --replicas=3

Kibana:
--------------

    oc process logging-kibana-template | oc create -f -

You may scale the resulting deployment normally for redundancy:

    oc scale dc/logging-kibana --replicas=2
    oc scale rc/logging-kibana-1 --replicas=2
EOF
