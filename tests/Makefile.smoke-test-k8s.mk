##
# k8s-tools.git smoke-tests part 2:
#   exercise the special form for ./k8s.mk <svc> -- <cmd>
#
# USAGE: ( from project root )
#   $ make smoke-test
##


SHELL:=bash
.SHELLFLAGS:=-eu -c
MAKEFLAGS=-sS --warn-undefined-variables

export KUBECONFIG:=./fake.profile.yaml
export _:=$(shell umask 066;touch ${KUBECONFIG})

include k8s.mk
include compose.mk
$(eval $(call compose.import, ▰, FALSE, k8s-tools.yml))
.DEFAULT_GOAL=help

all: clean build smoke-test 
build: #tux.require
clean: #compose.clean/k8s-tools.yml 
test.help:
	./k8s.mk help|grep ansible.adhoc
	./k8s.mk mk.namespace.filter/io|grep io.bash
	./k8s.mk mk.namespace.list | grep ansible
	./k8s.mk help.namespaces|grep ansible 
	./k8s.mk help helm
	
test.jb:
	echo foo=bar | make jb | jq .
	make jb foo=bar | jq .
test.stack:
	# echo '"key=val"'./compose.mk jb |./compose.mk flux.stage.clean flux.stage.push/testing flux.stage.pop/testing | jq .foo

test.ansible:
	# # call the block-in-file module 
	# echo path=.gitignore block=".flux.stage.*" | ./compose.mk jb.pipe | ./k8s.mk ansible.adhoc/blockinfile
	# # failure should fail 
	# # echo "'msg=failing as requested'" \
	# # | ./compose.mk jb.pipe \
	# # | ./compose.mk stream.peek  \
	# # | make ansible.adhoc/ansible.builtin.fail) \
	# # ; st=$$?; case $${st} in 0) exit 1; ;; esac 
	# echo "'msg=hello world'" | ./compose.mk jb | ./k8s.mk ansible.adhoc/ansible.builtin.debug

test.pygmentize:
	./compose.mk stream.pygmentize/k8s-tools.yml
	cat k8s-tools.yml | ./compose.mk stream.pygmentize

smoke-test: test.pygmentize test.ansible test.stack test.jb test.special.form test.standalone.jq 

test.standalone.jq:
	# echo 'testing without stdin '
	# ./compose.mk jq '{}' .
	# echo 'testing with stdin'
	# echo {} |./compose.mk jq .

test.special.form:
	# set -x && ./k8s.mk tux.require \
	# 	&& ./k8s.mk fission -- --help \
	# 	&& ./k8s.mk helmify -- --version \
	# 	&& ./k8s.mk kn -- --help \
	# 	&& ./k8s.mk k9s -- version \
	# 	&& ./k8s.mk kubectl -- version --client \
	# 	&& ./k8s.mk kompose -- version \
	# 	&& ./k8s.mk k3d --  --help \
	# 	&& ./k8s.mk helm -- --help \
	# 	&& ./k8s.mk promtool -- --version \
	# 	&& ./k8s.mk argo -- --help \
	# 	&& ./k8s.mk kind -- --version \
	# 	&& ./k8s.mk rancher -- --version \
	# 	&& ./k8s.mk kubefwd -- --help

#*/