MAKEFLAGS=-sS --warn-undefined-variables
# Smoke-test suite covers basics stuff about k8s-tools.yml directly, ignoring Makefile libs
all: build smoke-test 
build:; 
smoke-test:
	(\
		docker compose -f k8s-tools.yml run fission --help \
		&& docker compose -f k8s-tools.yml run helmify --version \
		&& docker compose -f k8s-tools.yml run kn --help \
		&& docker compose -f k8s-tools.yml run k9s version \
		&& docker compose -f k8s-tools.yml run kubectl --help \
		&& docker compose -f k8s-tools.yml run kompose version \
		&& docker compose -f k8s-tools.yml run k3d --help \
		&& docker compose -f k8s-tools.yml run helm --help \
		&& docker compose -f k8s-tools.yml run promtool --version \
		&& docker compose -f k8s-tools.yml run argo --help \
		&& docker compose -f k8s-tools.yml run kind --version \
		&& docker compose -f k8s-tools.yml run rancher --version \
		&& docker compose -f k8s-tools.yml run kubefwd --help) 2>&1 >/dev/null
