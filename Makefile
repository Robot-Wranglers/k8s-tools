#!/usr/bin/env -S make -s -S -f 
##
# Project Automation
#
# Typical usage: `make clean build test`
#
# https://clarkgrubb.com/makefile-style-guide
# https://gist.github.com/rueycheng/42e355d1480fd7a33ee81c866c7fdf78
# https://www.gnu.org/software/make/manual/html_node/Quick-Reference.html
##
SHELL := bash
.SHELLFLAGS?=-euo pipefail -c
MAKEFLAGS=-s -S --warn-undefined-variables
THIS_MAKEFILE:=$(abspath $(firstword $(MAKEFILE_LIST)))
.DEFAULT_GOAL:=help

.SUFFIXES:
.PHONY: docs

export SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
export PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})

export KUBECONFIG?=./fake.profile.yaml
export _:=$(shell umask 066;touch ${KUBECONFIG})

export KN_CLI_VERSION?=v1.14.0
export HELMIFY_CLI_VERSION?=v0.4.12
export K3D_VERSION?=v5.6.3

# Creates dynamic targets
include k8s.mk
$(eval $(call compose.import, ▰, TRUE, ${PROJECT_ROOT}/k8s-tools.yml))


## BEGIN: Top-level
##

all: init clean build test docs
init: mk.stat docker.stat
clean: flux.stage.clean
	@# Only used during development; normal usage involves build-on-demand.
	@# Cache-busting & removes temporary files used by build / tests 
	rm -f tests/compose.mk tests/k8s.mk tests/k8s-tools.yml
	find .| grep .tmp | xargs rm 2>/dev/null|| true
	
build: 
	@# Only used during development; normal usage involves build-on-demand.
	@# This uses explicit ordering that is required because compose 
	@# key for 'depends_on' affects the ordering for 'docker compose up', 
	@# but doesn't affect ordering for 'docker compose build'.

test: e2e-test integration-test smoke-test tui-test 

docs: docs.jinja #docs.mermaid


normalize: 

## BEGIN: CI/CD related targets
##
# cicd.clean: clean.github.actions
# clean.github.actions:
# 	@#
# 	@#
# 	query=".workflow_runs[].id" \
# 	&& org_name=`pynchon github cfg|jq -r .org_name` \
# 	&& repo_name=`pynchon github cfg|jq -r .repo_name` \
# 	&& repo_name="$${org_name}/$${repo_name}" \
# 	&& set -x && failed_runs=$$(\
# 		gh api --paginate \
# 			-X GET "/repos/$${repo_name}/actions/runs" \
# 			-F status=failure -q "$${query}") \
# 	&& for run_id in $${failed_runs}; do \
# 		echo "Deleting failed run ID: $${run_id}"; \
# 		gh api -X DELETE "/repos/$${repo_name}/actions/runs/$${run_id}"; \
# 	done

## BEGIN: Testing entrypoints
##
##
test-suite/%:
	@# Generic test-suite runner, just provide the test-suite name.
	@# (Names are taken from the files like "tests/Makefile.<name>.mk")
	@#
	@# USAGE: (run the named test-suite)
	@#   make test-suite/e2e
	@#
	@# USAGE: (run the named test from the named test-suite)
	@#   make test-suite/mad-science -- demo.python
	@#
	${make} io.print.div/${@}
	$(trace_maybe) \
	&& cd tests && bash ./bootstrap.sh \
	&& suite="`printf "${*}"|cut -d/ -f1`" \
	&& target="`printf "${*}"|cut -d/ -f2-`" \
	&& cp Makefile.$${suite}.mk Makefile \
	&& extra="$${target:$${targets:-}}" \
	&& env -i PATH=$${PATH} HOME=$${HOME} bash ${dash_x_maybe} -c "make ${MAKE_FLAGS} -f Makefile $${extra}" 

ttest tui-test: test-suite/tui/all
	@# TUI test-suite, exercising the embedded 'compose.mk:tux'
	@# container and various ways to automate tmux.
	
zonk: test-suite/smoke-test-k8s/test.ansible

ttest/%:; make test-suite/tui/${*}
stest smoke-test: test-suite/smoke-test-k8s/all test-suite/smoke-test-k8s-tools/all
	@# Smoke-test suite, exercising the containers we built.
	@# This just covers the compose file at k8s-tools.yml, ignoring Makefile integration

itest integration-test: test-suite/itest/all
	@# Integration-test suite.  This tests compose.mk and ignores k8s-tools.yml.
	@# Exercises container dispatch and the make/compose bridge.  No kubernetes.
itest/%:; make test-suite/itest/${*}

etest/% e2e/%:; make test-suite/e2e/${*}
etest e2e-test: test-suite/e2e/all
	@# End-to-end tests.  This tests k8s.mk + compose.mk + k8s-tools.yml
	@# by walking through cluster-lifecycle stuff inside a 
	@# project-local kubernetes cluster.

## BEGIN: Documentation related targets
##
define docs.builder.composefile
services:
  docs.builder: &base
    hostname: docs-builder
    build:
      context: .
      dockerfile_inline: |
        FROM python:3.9.21-bookworm
        RUN pip3 install --break-system-packages pynchon==2024.7.20.14.38 mkdocs==1.5.3 mkdocs-autolinks-plugin==0.7.1 mkdocs-autorefs==1.0.1 mkdocs-material==9.5.3 mkdocs-material-extensions==1.3.1 mkdocstrings==0.25.2
        RUN apt-get update && apt-get install -y tree jq
    entrypoint: bash
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
      - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
endef 
$(eval $(call compose.import.def,  ▰,  TRUE, docs.builder.composefile))
.mkdocs.build:; set -x && (make docs && mkdocs build --clean --verbose && tree site) ; find site docs|xargs chmod o+rw; ls site/index.html
docs.build: docs.builder/build ▰/docs.builder/.mkdocs.build
mkdocs: mkdocs.build mkdocs.serve
mkdocs.build build.mkdocs:; mkdocs build
mkdocs.serve serve:; mkdocs serve --dev-addr 0.0.0.0:8000

docs: docs.jinja #docs.mermaid

docs.jinja:
	@# Render all docs with jinja
	find docs | grep .j2 | sort | sed 's/docs\///g' | grep -v macros.j2 \
	| xargs -I% sh -x -c "make docs.jinja/% || exit 255"

docs.jinja/%: 
	@# Render the named docs twice (once to use includes, then to get the ToC)
	pynchon --version \
	&& $(call io.mktemp) && first=$${tmpf} \
	&& set -x && pynchon jinja render docs/${*} -o $${tmpf} --print \
	&& dest="docs/`dirname ${*}`/`basename -s .j2 ${*}`" \
	&& [ "${*}" == "README.md.j2" ] && mv $${tmpf} README.md || mv $${tmpf} $${dest}
docs.mermaid:; pynchon mermaid apply

docs.mmd: docs.mermaid

## BEGIN: targets for recording demo-gifs used in docs
##
## Uses charmbracelete/vhs to record console videos of the test suites 
## Videos for demos of the TUI
## Videos of the e2e test suite. ( Order matters here )
## Videos of the integration test suite. ( Order matters here )
##
vhs: vhs.e2e vhs.demo vhs.tui
vhs/%:
	set -x && rm -f img/`basename -s .tape ${*}`*.gif \
	&& ls docs/tape/${*}* \
	&& case $${suite:-} in \
		"") \
			echo no-suite \
			&& ls docs/tape/${*}* | make stream.peek \
			| xargs -I% -n1 sh -x -c "env -i PATH=$${PATH} HOME=$${HOME} vhs %" \
			&& chafa --invert --symbols braille --zoom img/${*}* \
			; ;; \
		*) \
			echo is-suite \
			&& pushd tests \
			&& bash ./bootstrap.sh \
			&& cp $${suite:-Makefile.e2e.mk} Makefile \
			&& ls ../docs/tape/${*}* | make stream.peek \
			| xargs -I% -n1 sh -x -c "env -i PATH=$${PATH} HOME=$${HOME} vhs %" \
			&& chafa --invert --symbols braille --zoom img/* ../img/docker.png \
			&& ls img/* | xargs -I% mv % ../img \
			; ;; \
	esac

vhs.demo:; suite=Makefile.itest.mk make vhs/demo
vhs.demo/%:; suite=Makefile.itest.mk make vhs/${*}
vhs.tui:; suite=Makefile.tui.mk make vhs/tui
vhs.tui/%:; make vhs/${*}
vhs.e2e:; suite=Makefile.e2e.mk make vhs/e2e
vhs.e2e/%:; suite=Makefile.e2e.mk make vhs/${*}