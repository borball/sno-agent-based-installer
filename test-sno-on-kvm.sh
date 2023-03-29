# used for my own test

ssh 192.168.58.14 kcli stop vm hub
ssh 192.168.58.14 kcli delete vm hub -y
ssh 192.168.58.14 'kcli create vm -P uuid=11111111-1111-1111-1111-000000000000 -P start=False -P memory=65536 -P numcpus=48 -P disks=[150,200,200] -P nets=["{\"name\":\"br-vlan58\",\"nic\":\"eth0\",\"mac\":\"de:ad:be:ff:10:01\"}"] hub'
ssh 192.168.58.14 kcli list vm

systemctl restart sushy-tools.service

./sno-iso.sh ./config-hub.yaml
cp hub/agent.x86_64.iso /var/www/html/iso/agent-hub.iso

./sno-install.sh 192.168.58.15:8080 dummy:dummy http://192.168.58.15/iso/agent-hub.iso 11111111-1111-1111-1111-000000000000

timeout 150 watch 'curl --silent http://192.168.58.80:8090/api/assisted-install/v2/clusters |jq '

until oc get node --kubeconfig hub/auth/kubeconfig 2>/dev/null | grep -m 1 "Ready"; do
  total_percentage=$(curl --silent http://192.168.58.80:8090/api/assisted-install/v2/clusters |jq '.[].progress.total_percentage')
  echo "Installation in progress $total_percentage/100"
  sleep 5;
done

oc get node --kubeconfig hub/auth/kubeconfig
oc get clusterversion --kubeconfig hub/auth/kubeconfig
