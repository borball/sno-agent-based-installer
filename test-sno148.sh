# used for my own test

rm -f ~/.cache/agent/image_cache/coreos-x86_64.iso
rm -rf sno148
./sno-iso.sh ./config-ipv6.yaml
cp sno148/agent.x86_64.iso /var/www/html/iso/agent-148.iso

./sno-install.sh 192.168.13.148 Administrator:superuser http://192.168.58.15/iso/agent-148.iso [2600:52:7:58::48]

until (oc get node --kubeconfig sno148/auth/kubeconfig 2>/dev/null | grep -m 1 "Ready" ); do
  total_percentage=$(curl --silent http://[2600:52:7:58::48]:8090/api/assisted-install/v2/clusters |jq '.[].progress.total_percentage')
  if [ ! -z $total_percentage ]; then
    echo "Installation in progress $total_percentage/100"
  fi
  sleep 5
done

oc get node --kubeconfig sno148/auth/kubeconfig
oc get clusterversion --kubeconfig sno148/auth/kubeconfig

echo "Installation in progress, please check it in 30m."
