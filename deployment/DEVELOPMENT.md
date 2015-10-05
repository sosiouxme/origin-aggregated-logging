## Development

The deployer `run.sh` can run outside a container. In that case it will use
your current kubeconfig context (which must be a cluster admin) to create everything.
You will need the Java JDK, openssl, and of course the openshift/oc client.
Check the script header for optional environment variables that can be supplied.
Define PROJECT to control where everything is created (`default` if not specified);
all others can be left to defaults just for a trial run.

    PUBLIC_MASTER_URL=https://master.example.com:8443 PROJECT=logging ./run.sh

There are some other useful templates for development, including builds
for these components and host-based PVs.

