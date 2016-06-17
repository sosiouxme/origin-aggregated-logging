FROM openshift/origin:v1.2.0
#FROM openshift/origin:latest

MAINTAINER OpenShift Development <dev@lists.openshift.redhat.com>

RUN yum install -y java-1.8.0-openjdk openssl && yum clean all

ENV BIN_DIR=/opt/deploy \
    SCRATCH_DIR=/etc/deploy/scratch \
    HOME=/etc/deploy \
    KUBECONFIG=/etc/deploy/.kubeconfig \
    WRITE_KUBECONFIG=1 \
    SECRET_DIR=/secret \
    LOGGING_VERSION=3

RUN mkdir -p ${HOME} ${SCRATCH_DIR} ${BIN_DIR} && chmod 777 ${HOME} && chmod 555 ${BIN_DIR}
COPY . ${BIN_DIR}
WORKDIR ${BIN_DIR}

VOLUME ${HOME}
ENTRYPOINT ["./run.sh"]
USER 1000
