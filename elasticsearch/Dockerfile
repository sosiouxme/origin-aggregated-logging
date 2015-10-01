FROM centos:centos7

MAINTAINER Eric Wolinetz <ewolinet@redhat.com>

EXPOSE 9200
EXPOSE 9300

ENV HOME=/opt/app-root/src \
  PATH=/opt/app-root/src/bin:/opt/app-root/bin:$PATH \
  JAVA_VER=1.8.0 \
  ES_VER=1.5.2

LABEL io.k8s.description="Elasticsearch container for allowing indexing and searching of aggregated logs" \
  io.k8s.display-name="Elasticsearch 1.5.2" \
  io.openshift.expose-services="9200:http, 9300:http" \
  io.openshift.tags="logging,elk,elasticsearch"

COPY elasticsearch.repo /etc/yum.repos.d/elasticsearch.repo

RUN rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch && \
  yum install -y -- setopt=tsflags=nodocs \
  java-1.8.0-openjdk \
  elasticsearch && \
  yum clean all && \
  mkdir -p ${HOME} && \
  ln -s /usr/share/java/elasticsearch /usr/share/elasticsearch && \
  /usr/share/elasticsearch/bin/plugin -i io.fabric8/elasticsearch-cloud-kubernetes/1.2.1 && \
  /usr/share/elasticsearch/bin/plugin -i io.fabric8.elasticsearch/openshift-elasticsearch-plugin/0.1 && \
  /usr/share/elasticsearch/bin/plugin -i com.floragunn/search-guard/0.5 && \
  mkdir /elasticsearch && \
  chmod -R og+w /usr/share/java/elasticsearch ${HOME} /elasticsearch

ADD *.sh /opt/app-root/src/
ADD *.yml /etc/elasticsearch

WORKDIR ${HOME}

CMD ["sh", "/opt/app-root/src/run.sh"]
