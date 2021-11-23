#!/bin/bash
set -euo pipefail
export SCONE_CLI_CONFIG="~/.cas/memcached-config.json"

# Random namespace for the session name.
export NAMESPACE=$RANDOM-$RANDOM-$RANDOM
export MC_SESSION_NAME=$NAMESPACE/memcached_policy
export CLIENT_SESSION_NAME=$NAMESPACE/client_policy

# MRENCLAVEs.
# Run `pull_images_and_determine_mrenclaves.sh` to export the correct, up-to-date
# MRENCLAVES to your environment.
source "${BASH_SOURCE%/*}/mrenclaves.sh"

# Parse CAS address.
# If provided SCONE_CAS_ADDR is an IPv4 address,
# create an entry for "cas" in /etc/hosts with
# such address. This is needed because SCONE CLI
# does not support IP addresses when attesting a CAS.
# If the provided SCONE_CAS_ADDR is a name, just use it.
SCONE_CAS_ADDR=${SCONE_CAS_ADDR:-"scone-cas.cf"}

if [[ $SCONE_CAS_ADDR =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    # NOTE: checking only for a generic IPv4 format (with no octet validation).
    CAS_ADDR="cas"
    echo "$SCONE_CAS_ADDR $CAS_ADDR" >> /etc/hosts
else
    CAS_ADDR=$SCONE_CAS_ADDR
fi

# Set release name if not provided. It is used in the sessions
# to configure dns and reach Memcached service.
export RELEASE_NAME=${RELEASE_NAME:-"memcached"}

# Attest CAS.
# Attest CAS before uploading the session file, accept CAS running in debug
# mode (--only_for_testing-debug), outdated TCB (-G) and hyper-thread enabled (-C).
echo "Attesting CAS..."
scone cas attest -G -C --only_for_testing-debug --only_for_testing-ignore-signer --accept-sw-hardening-needed --only_for_testing-trust-any "$CAS_ADDR"

# Submit policies.
# SCONE CLI utility will substitute the variables based on your
# environment (the variables exported in the lines above).
# That means that you can also customize such policies by exporting
# extra variables and referencing them on the templates.

echo "Creating random namespace: $NAMESPACE"
scone session create --use-env "${BASH_SOURCE%/*}/cas_namespace_template.yml"
echo -e "\nUploading Memcached policy..."
scone session create --use-env "${BASH_SOURCE%/*}/memcached_session_template.yml"
echo -e "\nUploading Memcached client policy..."
scone session create --use-env "${BASH_SOURCE%/*}/client_session_template.yml"

echo -e "\nWriting client environment variables to \"client_env\""


echo "export CLIENT_CONFIG_ID="$CLIENT_SESSION_NAME"/memcached_client" >> "${BASH_SOURCE%/*}/client_env"
echo "export SCONE_CAS_ADDR="$SCONE_CAS_ADDR"" >> "${BASH_SOURCE%/*}/client_env"


# Write the chart default values to chart_values.yml
# so that the we can easily copy and past into kubeapps.
# If the release name is not set, use "memcached".
echo -e "\nWriting chart values to \"chart_values.yml\""
echo "Note that your release name must be \""$RELEASE_NAME"\""
cat << EOF > ${BASH_SOURCE%/*}/chart_values.yml
## Release name: $RELEASE_NAME
# 
## Global Docker image parameters
## Please, note that this will override the image parameters, including dependencies, configured to use the global value
## Current available global Docker image parameters: imageRegistry and imagePullSecrets
##
# global:
#   imageRegistry: myRegistryName
#   imagePullSecrets:
#     - myRegistryKeySecretName
#   storageClass: myStorageClass

## Bitnami Memcached image version
## ref: https://hub.docker.com/r/bitnami/memcached/tags/
##
image:
  registry: registry.scontain.com:5050
  repository: sconecuratedimages/experimental
  tag: memcached-1-alpine-scone5.6.1
  ## Specify a imagePullPolicy
  ## Defaults to 'Always' if image tag is 'latest', else set to 'IfNotPresent'
  ## ref: http://kubernetes.io/docs/user-guide/images/#pre-pulling-images
  ##
  pullPolicy: Always
  ## Optionally specify an array of imagePullSecrets.
  ## Secrets must be manually created in the namespace.
  ## ref: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/
  ##
  pullSecrets:
    - name: sconeapps


# Configure SCONE parameters for memcached,
# as well as set up remote attestation.
scone:
  # If enabled, inject attestation information in
  # memcached environment: SCONE_CAS_ADDR, SCONE_LAS_ADDR
  # and SCONE_CONFIG_ID.
  attestation:
    enabled: true
    lasUseHostIP: true
    #las: 172.17.0.1
    cas: $SCONE_CAS_ADDR
    memcachedConfigID: $MC_SESSION_NAME/memcached

    # Enable attestation for tests
    testGetAndSetValueConfigID: memcached_test_policy/get_and_set_value

  # Define any SCONE-related variables.
  env:
    - name: SCONE_HEAP
      value: 2G
    - name: SCONE_MODE
      value: hw

useSGXDevPlugin: "scone"
#sgxEpcMem: 16

## Extra environment vars to pass.
## ref: https://github.com/bitnami/bitnami-docker-memcached#configuration
extraEnv: []

## String to partially override memcached.fullname template (will maintain the release name)
##
# nameOverride:

## Number of containers to run
replicaCount: 1

## String to fully override memcached.fullname template
##
# fullnameOverride:

# Cluster domain
clusterDomain: cluster.local

## Service parameters
##
##
service:
  ## Service type
  ##
  type: ClusterIP
  ## Memcached port
  ##
  port: 11211
  ## Specify the nodePort value for the LoadBalancer and NodePort service types.
  ## ref: https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport
  ##
  nodePort: ""
  ## Set the LoadBalancer service type to internal only.
  ## ref: https://kubernetes.io/docs/concepts/services-networking/service/#internal-load-balancer
  ##
  # loadBalancerIP:
  ## Annotations for the Memcached service
  ##
  annotations: {}

## Memcached containers' resource requests and limits
## ref: http://kubernetes.io/docs/user-guide/compute-resources/
##
resources:
  # We usually recommend not to specify default resources and to leave this as a conscious
  # choice for the user. This also increases chances charts run on environments with little
  # resources, such as Minikube. If you do want to specify resources, uncomment the following
  # lines, adjust them as necessary, and remove the curly braces after 'resources:'.
  limits: {}
  #   cpu: 100m
  #   memory: 128Mi
  requests:
    memory: 256Mi
    cpu: 250m


## Pod annotations
## ref: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/
##
podAnnotations: {}

## Pod affinity preset
## ref: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#inter-pod-affinity-and-anti-affinity
## Allowed values: soft, hard
##
podAffinityPreset: ""

## Pod anti-affinity preset
## Ref: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#inter-pod-affinity-and-anti-affinity
## Allowed values: soft, hard
##
podAntiAffinityPreset: soft

## Node affinity preset
## Ref: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#node-affinity
## Allowed values: soft, hard
##
nodeAffinityPreset:
  ## Node affinity type
  ## Allowed values: soft, hard
  type: ""
  ## Node label key to match
  ## E.g.
  ## key: "kubernetes.io/e2e-az-name"
  ##
  key: ""
  ## Node label values to match
  ## E.g.
  ## values:
  ##   - e2e-az1
  ##   - e2e-az2
  ##
  values: []

## Affinity for pod assignment. Evaluated as a template.
## Ref: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#affinity-and-anti-affinity
## Note: podAffinityPreset, podAntiAffinityPreset, and nodeAffinityPreset will be ignored when it's set
##
affinity: {}

## Node labels for pod assignment. Evaluated as a template.
## ref: https://kubernetes.io/docs/user-guide/node-selection/
##
nodeSelector: {}

## Tolerations for pod assignment. Evaluated as a template.
## ref: https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/
##
tolerations: []

## Pod priority
## ref: https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/
##
# priorityClassName: ""

## Persistence - used for dumping and restoring states between recreations
## Ref: https://github.com/memcached/memcached/wiki/WarmRestart
persistence:
  enabled: true
  ## Persistent Volume Storage Class
  ## If defined, storageClassName: <storageClass>
  ## If set to "-", storageClassName: "", which disables dynamic provisioning
  ## If undefined (the default) or set to null, no storageClassName spec is
  ##  set, choosing the default provisioner.  (gp2 on AWS, standard on
  ##  GKE, AWS & OpenStack)
  ##
  # storageClass: "-"
  ## Persistent Volume Claim annotations
  ##
  annotations: {}
  ## Persistent Volume Access Mode
  ##
  accessModes:
    - ReadWriteOnce
  ## Persistent Volume size
  ##
  size: 8Gi

## Args for running memcached
## Ref: https://github.com/memcached/memcached/wiki/ConfiguringServer
arguments:
  # - -m <maxMemoryLimit>
  # - -I <maxItemSize>
  # - -vv
EOF
