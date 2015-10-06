FROM centos:centos7

MAINTAINER Eric Wolinetz <ewolinet@redhat.com>

EXPOSE 9200
EXPOSE 9300
USER 0

ENV HOME=/opt/app-root/src \
  JAVA_VER=1.8.0 \
  ES_VER=1.5.2 \
  ES_CONF=/usr/share/elasticsearch/config/elasticsearch.yml

LABEL io.k8s.description="Elasticsearch container for allowing indexing and searching of aggregated logs" \
  io.k8s.display-name="Elasticsearch 1.5.2" \
  io.openshift.expose-services="9200:http, 9300:http" \
  io.openshift.tags="logging,elk,elasticsearch"

ADD elasticsearch.repo /etc/yum.repos.d/elasticsearch.repo
ADD run.sh install.sh ${HOME}/
ADD *.yml /usr/share/elasticsearch/config/
RUN ${HOME}/install.sh

WORKDIR ${HOME}
USER 1000
CMD ["sh", "/opt/app-root/src/run.sh"]
