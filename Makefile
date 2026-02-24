install-namespaces:
	kubectl create namespace databases
	kubectl create namespace apps

uninstall-namespaces:
	kubectl delete namespace databases
	kubectl delete namespace apps
	kubectl delete namespace traefik
	kubectl delete namespace cert-manager
	kubectl delete namespace metrics

install-traefik:
	helm repo add traefik https://traefik.github.io/charts
	helm repo update
	helm install -f infrastructure/traefik/values.yaml traefik traefik/traefik

uninstall-traefik:
	helm uninstall traefik --namespace traefik
	helm repo remove traefik

install-cert-manager:
	helm repo add jetstack https://charts.jetstack.io
	helm repo update
	helm install cert-manager -f infrastructure/cert-manager/values.yaml jetstack/cert-manager --namespace cert-manager --create-namespace
	kubectl apply -f infrastructure/cert-manager/cluster-issuer.yaml

uninstall-cert-manager:
	helm uninstall cert-manager --namespace cert-manager
	helm repo remove jetstack

install-mongodb:
	helm repo add mongodb https://mongodb.github.io/helm-charts
	helm repo update
	kubectl apply -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes/1.7.0/public/crds.yaml
	helm upgrade --install mongodb-kubernetes-operator mongodb/mongodb-kubernetes -n databases
	kubectl apply -f databases/mongodb/secrets.yaml
	kubectl apply -f databases/mongodb/mongodb.yaml
	kubectl apply -f databases/ui/mongo-express.yaml

uninstall-mongodb:
	helm uninstall mongodb-kubernetes-operator --namespace databases
	helm repo remove mongodb
	kubectl delete -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes/1.7.0/public/crds.yaml
	kubectl delete -f databases/mongodb/secrets.yaml
	kubectl delete -f databases/mongodb/mongodb.yaml
	kubectl delete -f databases/ui/mongo-express.yaml

install-mariadb:
	helm repo add mariadb-operator https://helm.mariadb.com/mariadb-operator
	helm install mariadb-operator-crds mariadb-operator/mariadb-operator-crds
	helm install mariadb-operator mariadb-operator/mariadb-operator
	kubectl apply -f databases/mariadb/secret.yaml
	kubectl apply -f databases/mariadb/backup-pvc.yaml
	helm install mariadb-cluster mariadb-operator/mariadb-cluster -n databases -f databases/mariadb/helm-values.yaml
	kubectl apply -f databases/ui/phpmyadmin.yaml

uninstall-mariadb:
	helm uninstall mariadb-operator
	helm uninstall mariadb-operator-crds
	helm uninstall mariadb-cluster --namespace databases
	kubectl delete -f databases/mariadb/secret.yaml
	helm delete mariadb-cluster --namespace databases
	kubectl delete pvc mariadb-backups --namespace databases
	kubectl delete -f databases/ui/phpmyadmin.yaml

install-redis:
	kubectl apply -f databases/redis/secrets.yaml
	helm install redis-cluster oci://registry-1.docker.io/cloudpirates/redis -f databases/redis/helm-values.yaml -n databases
	kubectl apply -f databases/ui/redisinsight.yaml

uninstall-redis:
	helm uninstall redis-cluster
	kubectl delete -f databases/redis/secrets.yaml
	kubectl delete -f databases/ui/redisinsight.yaml

add-registry:
	kubectl apply -f registry/credentials.yaml