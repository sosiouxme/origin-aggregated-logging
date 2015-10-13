FROM rhel7:latest

MAINTAINER OpenShift Development <dev@lists.openshift.redhat.com>

EXPOSE 5601

ENV KIBANA_VER=4.1.1 \ 
    ES_HOST=localhost \ 
    ES_PORT=9200

LABEL io.k8s.description="Kibana container for querying Elasticsearch for aggregated logs" \
  io.k8s.display-name="Kibana" \
  io.openshift.expose-services="5601:http" \
  io.openshift.tags="logging,elk,kibana"

ADD efk.repo /etc/yum.repos.d/elasticsearch.repo

RUN yum install -y --setopt=tsflags=nodocs \
    --disablerepo '*' \
    --enablerepo rhel-7-server-rpms \
    --enablerepo rhel-7-server-extras-rpms\
    --enablerepo efkstack \
      kibana origin-kibana && \
      yum clean all && \
      chmod -R og+w /opt/app-root/src

COPY kibana.yml /opt/app-root/src/config/kibana.yml
COPY run.sh /opt/app-root/src/run.sh

USER default

CMD ["sh", "run.sh"]
