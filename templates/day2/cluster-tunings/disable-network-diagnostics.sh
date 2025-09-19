oc patch network.operator.openshift.io cluster --type='json' -p=['{"op": "replace", "path": "/spec/disableNetworkDiagnostics", "value":true}']
