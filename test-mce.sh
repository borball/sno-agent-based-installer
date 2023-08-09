# used for my own test

ssh 192.168.58.14 kcli stop vm mce
ssh 192.168.58.14 kcli delete vm mce -y
ssh 192.168.58.14 'kcli create vm -P uuid=11111111-1111-1111-1234-000000000001 -P start=False -P memory=40960 -P numcpus=24 -P disks=[120,120,120] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:86\"}"] mce'
ssh 192.168.58.14 kcli list vm

systemctl restart sushy-tools.service

rm -f ~/.cache/agent/image_cache/coreos-x86_64.iso
rm -rf mce
./sno-iso.sh samples/config-mce.yaml
cp mce/agent.x86_64.iso /var/www/html/iso/mce.iso

./sno-install.sh samples/config-mce.yaml


oc get node --kubeconfig mce/auth/kubeconfig
oc get clusterversion --kubeconfig mce/auth/kubeconfig

echo "Installation in progress, please check it in 30m."

echo "Installation in progress, take a coffee and come back in 30m."

until oc --kubeconfig mce/auth/kubeconfig get clusterversionn | grep -m 1 "Cluster version is"; do sleep 1; done

echo
oc get nodes -kubeconfig mce/auth/kubeconfig
echo
oc get clusterversion -kubeconfig mce/auth/kubeconfig
echo
oc get co -kubeconfig mce/auth/kubeconfig
echo
