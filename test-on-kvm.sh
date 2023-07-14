# used for my own test

ssh 192.168.58.14 kcli stop vm testkvm
ssh 192.168.58.14 kcli delete vm testkvm -y
ssh 192.168.58.14 'kcli create vm -P uuid=11111111-1111-1111-1234-000000000000 -P start=False -P memory=20480 -P numcpus=16 -P disks=[150,100,100] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:85\"}"] testkvm'
ssh 192.168.58.14 kcli list vm

systemctl restart sushy-tools.service

rm -f ~/.cache/agent/image_cache/coreos-x86_64.iso
rm -rf testkvm
./sno-iso.sh samples/config-testkvm.yaml
cp testkvm/agent.x86_64.iso /var/www/html/iso/testkvm.iso

./sno-install.sh samples/config-testkvm.yaml


oc get node --kubeconfig testkvm/auth/kubeconfig
oc get clusterversion --kubeconfig testkvm/auth/kubeconfig

echo "Installation in progress, please check it in 30m."
