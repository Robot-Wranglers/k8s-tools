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
.PHONY: docs demos

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
	
normalize build: 
	@# Only used during development; normal usage involves build-on-demand.
	@# This uses explicit ordering that is required because compose 
	@# key for 'depends_on' affects the ordering for 'docker compose up', 
	@# but doesn't affect ordering for 'docker compose build'.

test: e2e-test integration-test smoke-test tui-test 

docs: docs.jinja #docs.mermaid


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
	&& set -x && cd tests \
	&& suite="`printf "${*}"|cut -d/ -f1`" \
	&& target="`printf "${*}"|cut -d/ -f2-`" \
	&& cp Makefile.$${suite}.mk Makefile \
	&& extra="$${target:$${targets:-}}" \
	&& make -f Makefile.$${suite}.mk $${extra}

ttest tui-test: test-suite/tui/all
	@# TUI test-suite, exercising the embedded 'compose.mk:tux'
	@# container and various ways to automate tmux.
	
ttest/%:; make test-suite/tui/${*}
etest e2e e2e-test:
	@# End-to-end tests.  This tests k8s.mk + compose.mk + k8s-tools.yml
	@# by walking through cluster-lifecycle stuff inside a 
	@# project-local kubernetes cluster.
	make -f demos/cluster-lifecycle.mk

demos demos.test demo-test test.demos:
	@# Runs one or more of the demos
	ls demos/$${demo:-*}mk \
	| grep -v cluster-lifecycle \
	| xargs -I% -n1 script -q -e -c "env -i PATH=$${PATH} HOME=$${HOME} bash -x -c \"make -f %\"||exit 255"
demo/% demos/%:; fname=${*} make demos

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

## BEGIN: CI/CD related targets
##

cicd.clean: clean.github.actions
clean.github.actions:
	@#
	@#
	gh run list --status failure --json databaseId \
	| ${stream.peek} | jq -r '.[].databaseId' \
	| xargs -n1 -I% sh -x -c "gh run delete %"