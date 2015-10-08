# Origin-Aggregated-Logging

This repo contains the image definitions of the components of the logging
stack as well as tools for building and deploying them.

To generate the necessary images from github source in your OpenShift
Origin deployment, follow directions below.

To deploy the components from built or supplied images, see the
[deployer](./deployment).

## Components

The logging subsystem consists of multiple components commonly abbreviated
as the "ELK" stack (though modified here to be the "EFK" stack).

### ElasticSearch

ElasticSearch is a Lucene-based indexing object store into which all logs
are fed. It should be deployed with redundancy, can be scaled up using
more replicas, and should use persistent storage.

### Fluentd

Fluentd is responsible for gathering log entries from nodes, enriching
them with metadata, and feeding them into ElasticSearch.

### Kibana

Kibana presents a web UI for browsing and visualizing logs in ElasticSearch.

### Logging auth proxy

In order to authenticate the Kibana user against OpenShift's Oauth2, a
proxy is required that runs in front of Kibana.

### Deployer

The deployer enables the user to generate all of the necessary
key/certs/secrets and deploy all of the components in concert.

## Defining local builds

Choose the project you want to hold your logging infrastructure. It can be
any project.

Instantiate the [dev-builds template](hack/templates/dev-builds.yaml) to
define builds for all images and ImageStreams to hold their output. You
can do this before or after deployment. Deployment defines the same
ImageStreams, so it is normal to see errors about already-defined
ImageStreams when building from source and deploying.

The template has parameters to specify the repository and branch to use
for the builds. The defaults are for origin master. To develop your own
images, you can specify your own repos and branches as needed.

A word about the openshift-auth-proxy: it depends on the "node" base
image, which is intended to be the DockerHub nodejs base image. If you
have defined all the standard templates, they include a nodejs builder image
that is also called "node", and this will be used instead of the intended
base image, causing the build to fail. You can delete it to resolve this
problem:

    oc delete is/node -n openshift

The builds should be started once defined; if any fail, you can retry
them with

    oc start-build <component>

e.g.

    oc start-build openshift-auth-proxy

With the standard deployment, once a build completes successfully it
will be automatically deployed.

## Running the deployer script locally

When developing the deployer, it is fairly tedious to rebuild the image
and redeploy it just for tiny iterative changes.  The deployer script
is designed to be run either in the deployer image or directly. It
requires the openshift and oc binaries as well as the Java 8 JDK. When
run directly, it will use your current client context to create all
the objects, but you must still specify at least the PROJECT env var in
order to create everything with the right parameters. E.g.:

    cd deployment
    PROJECT=logging ./run.sh

There are a number of environment this script looks at which are useful
when running directly; check the script headers for details.

