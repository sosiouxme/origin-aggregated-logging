#!/bin/bash 

set -ex

rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch
yum install -y -- setopt=tsflags=nodocs \
  java-1.8.0-openjdk \
  elasticsearch
yum clean all

mkdir -p ${HOME}
ln -s /usr/share/java/elasticsearch /usr/share/elasticsearch
/usr/share/elasticsearch/bin/plugin -i io.fabric8/elasticsearch-cloud-kubernetes/1.2.1
/usr/share/elasticsearch/bin/plugin -i io.fabric8.elasticsearch/openshift-elasticsearch-plugin/0.1
/usr/share/elasticsearch/bin/plugin -i com.floragunn/search-guard/0.5
mkdir /elasticsearch
chmod -R og+w /usr/share/java/elasticsearch ${HOME} /elasticsearch
