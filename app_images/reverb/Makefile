build-arm:
	docker buildx build --platform linux/arm64 -t hub.connoisseur-suite.co.uk/test/reverb:latest -f Dockerfile . --push
build:
	cp .env.example .env
	docker buildx build --platform linux/amd64 -t hub.connoisseur-suite.co.uk/test/reverb:latest -f Dockerfile . --push