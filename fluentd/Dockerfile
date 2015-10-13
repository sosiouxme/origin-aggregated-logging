FROM rhel7:latest

MAINTAINER OpenShift Development <dev@lists.openshift.redhat.com>

ENV HOME=/opt/app-root/src \
  PATH=/opt/app-root/src/bin:/opt/app-root/bin:$PATH \
  RUBY_VERSION=2.0 \
  FLUENTD_VERSION=0.12.6 \
  GEM_HOME=/opt/app-root/src

LABEL io.k8s.description="Fluentd container for collecting of docker container logs" \
  io.k8s.display-name="Fluentd 0.12.6" \
  io.openshift.expose-services="9200:http, 9300:http" \
  io.openshift.tags="logging,elk,fluentd"

ADD efk.repo /etc/yum.repos.d/elasticsearch.repo

RUN yum install -y --setopt=tsflags=nodocs \
    --disablerepo '*' \
    --enablerepo rhel-7-server-rpms \
    --enablerepo rhel-7-server-extras-rpms \
    --enablerepo rhel-7-server-optional-rpms \
    --enablerepo efkstack \
    fluentd rubygem-fluent-plugin-flatten-hash rubygem-fluent-plugin-kubernetes_metadata_filter && \
    yum clean all && \
    mkdir -p ${HOME}

ADD out_elasticsearch*.rb ${GEM_HOME}/gems/fluent-plugin-elasticsearch-1.0.0/lib/fluent/plugin/
ADD fluent.conf /etc/fluent/fluent.conf

WORKDIR ${HOME}

CMD ["fluentd"]
