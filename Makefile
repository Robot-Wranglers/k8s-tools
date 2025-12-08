#!/usr/bin/env -S make -s -S -f 
##
# Project Automation
#
# Typical usage: `make clean build test`
##
SHELL := bash
.SHELLFLAGS?=-euo pipefail -c
MAKEFLAGS=-s -S --warn-undefined-variables
THIS_MAKEFILE:=$(abspath $(firstword $(MAKEFILE_LIST)))

.PHONY: docs demos demos/cmk README.md bin bundle

export SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
export PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})
export KUBECONFIG?=./local.cluster.yml
export _:=$(shell umask 066;touch ${KUBECONFIG})
export MKDOCS_LISTEN_PORT=8001

# # export KN_CLI_VERSION?=v1.14.0
# # export HELMIFY_CLI_VERSION?=v0.4.12

include .cmk/compose.mk
$(call compose.import, file=k8s-tools.yml)
$(call mk.import.plugins, docs.mk actions.mk)
# include docs/docs.mk
docs: flux.stage/documentation docs.pynchon.build docs.README.static docs.jinja docs.pynchon.dispatch/.docs.build
docs.README.static: README.md #demos/README.md demos/cmk/README.md
README.md:; ${docs.render.mirror}

serve: docs.serve
__main__: init clean build test docs
init: mk.stat docker.stat 

clean: flux.stage.clean
	find . | grep .tmp | xargs rm 2>/dev/null || true

build: build.bin tux.require build.services 
	@# Containers are normally pulled on demand, 
	@# but pre-caching cleans up the build logs.
	${jb} foo=bar | ${jq} . > /dev/null

build.services: \
	k8s-tools.build.quiet/k8s \
	k8s-tools.build.quiet/dind \
	k8s-tools.build.quiet

build.bin bin bundle:
	# shebang="#!/usr/bin/env -S K8SMK_STANDALONE=1 bash\n"
	$(call log.target, Refreshing main bundle)
	set -x \
	&& bin=./k8s ${make} mk.fork/k8s.mk,k8s-tools.yml

test normalize: # NOP

demos demos.test demo-test test.demos:
	set -x && ls demos/*.mk \
	| xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"

demo:
	@# Interactive selector for which demo to run.
	pattern='*.mk' dir=demos/ ${make} flux.select.file/mk.select

demos/cmk:
	set -x && ls demos/cmk/*.cmk | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"

sync:
	cp -v ../compose.mk/docs/theme/css/* docs/theme/css
	cp -v ../compose.mk/docs/theme/js/* docs/theme/js
	cp -v ../compose.mk/compose.mk .
