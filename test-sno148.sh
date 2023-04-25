# used for my own test

rm -f ~/.cache/agent/image_cache/coreos-x86_64.iso
rm -rf sno148
./sno-iso.sh samples/config-sno148.yaml
cp sno148/agent.x86_64.iso /var/www/html/iso/sno148.iso

./sno-install.sh samples/config-sno148.yaml

oc get node --kubeconfig sno148/auth/kubeconfig
oc get clusterversion --kubeconfig sno148/auth/kubeconfig

echo "Installation in progress, please check it in 30m."
