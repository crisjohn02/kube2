deploy:
	kubectl apply -f namespace.yaml
	kubectl apply -f secrets.yaml
	kubectl apply -f configmap.yaml
	kubectl apply -f deployment.yaml
	kubectl apply -f ingress.yaml

uninstall:
	kubectl delete -f namespace.yaml
	kubectl delete -f secrets.yaml
	kubectl delete -f configmap.yaml
	kubectl delete -f deployment.yaml
	kubectl delete -f service.yaml

migrate:
	kubectl apply -f migration.yaml