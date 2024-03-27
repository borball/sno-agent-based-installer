# Scripts to mirror the operators and openshift images.

## mirror-registry.sh

You can change the settings below in script mirror-registry.sh to fit your environment:

LOCAL_REGISTRY="registry.service.local:5000"
LOCAL_REPOSITORY="library/openshift-release-dev"
PRODUCT_REPO="openshift-release-dev"
LOCAL_SECRET_JSON="./pull-secret.json"

Then you can run it to mirror the openshift images:

```shell
./mirror-registry.sh 4.12.53

```

In the end the command output your will see text below:

```
Success
Update image:  hub-helper:5000/library/openshift-release-dev:4.12.53-x86_64
Mirror prefix: hub-helper:5000/library/openshift-release-dev
Mirror prefix: hub-helper:5000/library/openshift-release-dev:4.12.53-x86_64

To use the new mirrored repository to install, add the following section to the install-config.yaml:

imageContentSources:
- mirrors:
  - hub-helper:5000/library/openshift-release-dev
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - hub-helper:5000/library/openshift-release-dev
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev


To use the new mirrored repository for upgrades, use the following to create an ImageContentSourcePolicy:

apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: example
spec:
  repositoryDigestMirrors:
  - mirrors:
    - hub-helper:5000/library/openshift-release-dev
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - hub-helper:5000/library/openshift-release-dev
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev


To apply signature configmaps use 'oc apply' on files found in ./4.12.53

Configmap signature file 4.12.53/signature-sha256-b584f5458fb94611.json created
```

Save the content of imageContentSources and ImageContentSourcePolicy in files.

## mirror-operators.sh

You can change the settings below in script mirror-operators.sh to fit your environment:

LOCAL_REGISTRY="registry.service.local:5000"
LOCAL_REPOSITORY="library/openshift-release-dev"
PRODUCT_REPO="openshift-release-dev"
LOCAL_SECRET_JSON="./pull-secret.json"

Then you can run it to mirror the openshift images:

```shell
./mirror-registry.sh 4.12.53

```