# used for my own test

node="testkvm"

ssh 192.168.58.14 kcli stop vm "$node"
ssh 192.168.58.14 kcli delete vm "$node" -y
ssh 192.168.58.14 'kcli create vm -P uuid=11111111-1111-1111-1234-000000000001 -P start=False -P memory=40960 -P numcpus=24 -P disks=[150] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:86\"}"] "$node"'
ssh 192.168.58.14 kcli list vm

systemctl restart sushy-tools.service

rm -f ~/.cache/agent/image_cache/coreos-x86_64.iso
rm -rf "$node"
./sno-iso.sh samples/config-"$node".yaml
cp "$node"/agent.x86_64.iso /var/www/html/iso/"$node".iso

./sno-install.sh samples/config-"$node".yaml


oc get node --kubeconfig "$node"/auth/kubeconfig
oc get clusterversion --kubeconfig "$node"/auth/kubeconfig

echo "Installation in progress, please check it in 30m."

echo "Installation in progress, take a coffee and come back in 30m."

until oc --kubeconfig "$node"/auth/kubeconfig get clusterversionn | grep -m 1 "Cluster version is"; do sleep 1; done

echo
oc get nodes -kubeconfig "$node"/auth/kubeconfig
echo
oc get clusterversion -kubeconfig "$node"/auth/kubeconfig
echo
oc get co -kubeconfig "$node"/auth/kubeconfig
echo
