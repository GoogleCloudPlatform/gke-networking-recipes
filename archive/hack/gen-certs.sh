WD=$(dirname "$0")
WD=$(cd "$WD"; pwd)

set -e

openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=example Inc./CN=gateway.local' -keyout /tmp/root.key -out /tmp/root.crt
openssl req -out /tmp/cert.csr -newkey rsa:2048 -nodes -keyout /tmp/cert.key -subj "/CN=gateway.local/O=example organization"
openssl x509 -req -days 365 -CA /tmp/root.crt -CAkey /tmp/root.key -set_serial 0 -in /tmp/cert.csr -out /tmp/cert.crt
kubectl create -n istio-system secret tls service-apis-cert --key=/tmp/cert.key --cert=/tmp/cert.crt --dry-run=client -oyaml > "${WD}"/../certificate.yaml
