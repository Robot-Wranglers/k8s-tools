##
# k8s-tools.git integration tests, 
# exercising compose.mk plus the compose file
#   
#
# Usage: 
#
#   # from project root
#   $ make etest
##

# Standard boilerplate for make itself, nothing to see here.
SHELL := bash
MAKEFLAGS=-sS --warn-undefined-variables
.DEFAULT_GOAL=help
.SHELLFLAGS := -euo pipefail -c
.SUFFIXES:

# Set a default for KUBECONFIG so that user doesn't need to provide it. 
# We create this file if it doesn't exist 
export KUBECONFIG:=./fake.profile.yaml
export _:=$(shell umask 066;touch ${KUBECONFIG})

# Include compose.mk so we can use `compose.import` macro, and
# otherwise exercise base-targets that are provided by the lib
include compose.mk

# Load all services from 1 compose file, *not* into the root namespace.
$(eval $(call compose.import, ▰, FALSE, cm-tools.yml))

# Load all services from 2 compose files into 1 namespace.
$(eval $(call compose.import, ▰, TRUE, docker-compose.yml))
$(eval $(call compose.import, ▰, FALSE, k8s-tools.yml))

.DEFAULT_GOAL := all 
all: #tux.require #docker-compose.build.quiet #k8s-tools.build.quiet/k8s k8s-tools.build.quiet/k3d
	printf '\n' && set -x \
	&& make \
		test.mk \
		flux.stage/core-compose \
		demo demo.double.dispatch \
		test.dispatch \
		test.dispatch.retvals \
		test.compose.pipes \
		test.compose.services \
		test.import.root \
		test.main.bridge \
		test.multiple.compose.files \
		test.docker.core \
		flux.stage/core-tui \
		test.ticker \
		test.containerized.tty.output \
		flux.stage/core-flux \
		test.flux.lib

test.mk:
	./compose.mk \
		mk.set/foo/bar mk.get/foo \
		mk.ifdef/foo mk.ifndef/baz

test.flux.if.then:
	./compose.mk flux.if.then/flux.ok,flux.ok
	./compose.mk flux.if.then/flux.fail,flux.ok
	./compose.mk flux.do.when/flux.fail,flux.ok
	./compose.mk flux.do.when/flux.ok,flux.ok

test.stage:
	# declare a stage
	./compose.mk flux.stage/${@}
	${jb.run} foo=bar | ./compose.mk flux.stage.push/${@} 
	./compose.mk flux.stage.pop/${@}
	./compose.mk flux.stage/test flux.stage.clean; (ls .flux.stage.test 2>/dev/null && exit 1 || exit 0)
	echo 33 | ./compose.mk flux.stage/test flux.stage.push; (ls .flux.stage.test 2>/dev/null && exit 1 || exit 0)
	 
test.signals: flux.stage/test-signals
	# successful because this uses the signal handler 
	./k8s.mk mk.interrupt
	./compose.mk mk.interrupt
	# not successful because it's not installed for this makefile 
	# ! make mk.interrupt
	
demo: ▰/debian/self.demo
	@# New target declaration that we can use to run stuff
	@# inside the `debian` container.  The syntax conventions
	@# are configured by the `compose.import` call we used above.

test.ticker:
	@# FIXME: timeout kills the whole process?
	@# text=" testing ticker " make flux.timeout/2/tux.widget.ticker || true

# Displays platform info to show where target is running.
# Since this target is intended to be private, we will 
# prefix "self" to indicate it should not run on host.
self.demo:
	. /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v
demo.double.dispatch: ▰/debian/self.demo ▰/alpine/self.demo

test.containerized.tty.output: 
	cmd='sleep 2' label='testing gum spinner inside container' make io.gum.spin
test.docker.core: \
	flux.stage/core-docker \
		test.docker.run
test.import.root:
	make io.print.div label="${bold_cyan}${@}${no_ansi}"
	$(call log, ${dim_cyan}Test import-to-root argument for compose.import)
	# test that the 4th argument for
	# import-to-root-namespace is honored
	! echo uname | make chef/pipe 2>/dev/null
	echo uname | make cm-tools/chef/pipe 2>/dev/null
	echo uname | make k8s-tools/k3d/shell/pipe

test.main.bridge:
	make io.print.div label="${cyan}${@}${no_ansi}"
	$(call log, ${dim_cyan}Test service enumeration\nTarget @ <compose_file>.services)
	make k8s-tools.services
	$(call log, ${dim_cyan}Test detection\nTarget @ <compose_file>/get_shell)
	make k8s-tools/k8s/get_shell

test.multiple.compose.files:
	make io.print.div label="${cyan}${@}${no_ansi}"
	$(call log, ${dim_cyan}Test services enumeration, 2nd file\nTarget @ <compose_file>/<svc>.services)
	make docker-compose.services
	$(call log, ${dim_cyan}Test Streaming commands, 2nd file\nTarget @ <compose_file>/<svc>/pipe)
	echo uname -n -v | make docker-compose/debian/pipe \

test.compose.pipes:
	# make io.print.div label="${cyan}${@}${no_ansi}"
	# $(call log, ${dim_cyan}Streaming commands to container\nTarget @ <svc>/shell/pipe)
	# echo uname -n -v | make k8s-tools/k8s/shell/pipe
	# $(call log, ${dim_cyan}Test streaming commands to container\nTarget @ <compose_file_stem><svc>/shell/pipe)
	# echo uname -n -v | make k8s-tools/k8s/shell/pipe
	# printf "\n${dim_cyan}Test streaming data to container\nTarget @ <svc>/shell/pipe ${no_color}\n"
	# echo 'foo: bar' | make k8s-tools/yq/pipe
	# set -x && echo '{"foo":"bar"}' | cmd='.foo' make k8s-tools/jq/pipe

test.compose.services:
	make io.print.div label="${cyan}${@}${no_ansi}"
	printf "\n${dim_cyan}Test main entrypoints\nTarget @ <compose_file>/<svc> ${no_color}\n"
	make k8s-tools/helm > /dev/null
	make k8s-tools/kubectl > /dev/null
	make k8s-tools/k3d cmd='--version'

test.dispatch.retvals:
	printf "\n${dim_cyan}Checking dispatch return codes:${no_color}\n"
	! (echo exit 1 | make docker-compose/debian/shell/pipe 2>/dev/null)
	echo exit  | make docker-compose/debian/shell/pipe

test.dispatch:
	make io.print.div label="${cyan}${@}${no_ansi}"
	printf "\n${dim_cyan}Dispatch using private base target:${no_color}\n"
	echo uname | pipe=yes make ▰/debian
	printf "\n${dim_cyan}Dispatch using debian container:${no_color}\n"
	make ▰/debian/self.container.dispatch
	printf "\n${dim_cyan}Dispatch using alpine container:${no_color}\n"
	make ▰/alpine/self.container.dispatch
self.container.dispatch:
	printf "in container `hostname`, platform info: `uname`\n"

test.flux.lib: test.flux.finally test.flux.try.except.finally test.flux.mux test.flux.dmux test.flux.loop

test.flux.try.except.finally:
	make flux.try.except.finally/flux.fail,flux.ok,flux.ok
	! make flux.try.except.finally/flux.ok,flux.ok,flux.fail
	# except fails, but try succeeds so it never runs
	make flux.try.except.finally/flux.ok,flux.fail,flux.ok
	! make flux.try.except.finally/flux.fail,flux.fail,flux.ok
	make flux.try.except.finally/flux.ok,flux.ok,flux.ok

test.flux.finally:
	# demo of using finally/always functionality in a pipeline.  touches a tmpfile 
	# somewhere in the middle of a failing pipeline without getting to the cleanup 
	# task, and it should be cleaned up anyway.
	bash -i -c "(make \
		flux.finally/.file.cleanup \
		.file.touch flux.fail file-cleanup || true)"
	# NB: cannot assert this from here because cleanup only runs when the *test process* exits
	# ! ls .tmp.test.flux.finally	
.file.touch:
	touch .tmp.test.flux.finally

.file.cleanup:
	rm .tmp.test.flux.finally

test.flux.loop:
	make k8s-tools.dispatch/k8s/flux.loop/2/io.time.wait

test.flux.dmux:
	# echo {} | make flux.dmux/k8s-tools/yq,k8s-tools/jq
	# echo {} | make flux.split/k8s-tools/yq,k8s-tools/jq

test.flux.retry:
	! interval=1 make flux.retry/3/flux.fail

test.flux.apply:
	make flux.apply.later/2/io.time.wait/1

test.flux.mux:
	make flux.mux targets="io.time.wait,io.time.wait,io.time.wait/2" | jq .
	make flux.join targets="io.time.wait,io.time.wait,io.time.wait/2" | jq .
	make flux.mux/io.time.wait

test.docker.run:
	img=python:3.11-bookworm make docker.run/flux.ok
	echo hello-python-docker1 | make .test.docker.run.def
	echo hello-python-docker2 | entrypoint=cat cmd=/dev/stdin img=python:3.11-slim-bookworm make docker.run.sh
	entrypoint=python cmd='--version' img=python:3.11-slim-bookworm make docker.run.sh
	echo {} | cmd=. img=ghcr.io/jqlang/jq:1.7.1 make docker.start

.test.docker.run.def:
	entrypoint=python def=script.demo.docker.run.def \
	img=python:3.11-slim-bookworm make docker.run.def
define script.demo.docker.run.def 
# python script 
import sys
print(['input',sys.stdin.read().strip()])
endef
