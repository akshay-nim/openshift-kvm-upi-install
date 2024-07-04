oc get secret/pull-secret -n openshift-config --template='{{index .data ".dockerconfigjson" | base64decode}}' > global_pull_secret.yaml
oc registry login --registry="registry.redhat.io" --auth-basic="vtas-eng:V4La@24!" --to=global_pull_secret.yaml
oc registry login --registry="registry.connect.redhat.com" --auth-basic="vtas-eng:V4La@24!" --to=global_pull_secret.yaml
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=global_pull_secret.yaml

