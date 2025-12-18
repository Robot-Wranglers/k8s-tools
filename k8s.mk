#!/usr/bin/env -S K8SMK_STANDALONE=1 make -f
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# k8s.mk: 
#   Automation library/framework/tool building on compose.mk and k8s-tools.yml
#
# DOCS: https://robot-wranglers.github.io/k8s-tools#k8smk
#
# LATEST: https://robot-wranglers.github.io/k8s-tools/tree/master/k8s.mk
#
# FEATURES:
#   1) ....................................................
#   1) ....................................................
#   1) ....................................................
#   1) ....................................................
#
# USAGE: ( For Integration )
#   # Add this to your project Makefile
#   include k8s.mk
#   demo: ▰/k8s/self.demo
#   self.demo:
#       kubectl --help
#		helm --help
#
# USAGE: ( Stand-alone tool mode )
#   ./k8s.mk help
#
# APOLOGIES:
#   In advance if you're checking out the implementation.  This is just 
#   unavoidably gnarly in a lot of places.  No one likes a file this long,
#   and especially make-macros are not the most fun stuff to read or write.
#   Breaking this apart could make internal development easier but would 
#   complicate boilerplate required for integration with external projects.  
#   Pull requests are welcome! =P  
#
# REFS:
#   `[1]`: https://robot-wranglers.github.io/k8s-tools
#
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
ifndef GLYPH_K8S
GLYPH_K8S=${green}⑆${dim}
log.k8s=$(call log, ${GLYPH_K8S} ${1})
k8s.log=${log.k8s}
k8s.log.part1=$(call log.part1,${GLYPH_K8S}${1})
k8s.log.part2=$(call log.part2,${1})

# Hints for exactly how k8s.mk is being invoked 
export K8SMK_STANDALONE?=0
export K8S_MK_SRC=k8s.mk
export TRACE?=$(shell echo "$${TRACE:-$${trace:-0}}")

K8S_TOOLS=$(shell dirname ${K8S_MK_SRC} || echo .)/k8s-tools.yml
ifeq ($(K8SMK_STANDALONE),1)
export K8S_MK_LIB=0
else
export K8S_MK_LIB=1
endif

#ifeq ($(strip $(if $(filter undefined,$(origin CMK_SRC)),,$(CMK_SRC))),)
#endif
#ifeq ($(filter ${MAKEFILE_LIST},compose.mk),)
#ifneq (,$(findstring compose.mk,${MAKEFILE_LIST}))
#$(error ${MAKEFILE_LIST})
#endif
ifeq ($(K8SMK_STANDALONE),1)
#$(shell >&2 echo "stand-alone mode; importing tools containers froms k8s-tools.yml")
$(call compose.import, file=${K8S_TOOLS})
#$(shell >&2 echo "done importing k8s-tools")
endif
ifeq ($${CMK_SRC:-},)
endif

ifeq (${TRACE},1)
$(shell printf "trace=$${TRACE} quiet=$${quiet} verbose=$${verbose:-} ${yellow}CMK_SRC=$${CMK_SRC:-} __interpreter__=$${__interpreter__:-} CMK_INTERPRETING=$${CMK_INTERPRETING:-}${no_ansi}\n" > /dev/stderr)
endif 

# Extra repos that are included in 'docker.images' output.  
# This is used by `compose.mk` to differentiate "local" images.
export CMK_EXTRA_REPO:=k8s

DEFAULT_KUBECONFIG:=./local.cluster.yml

# How long to wait when checking if namespaces/pods are ready
export K8S_POLL_DELTA?=23

# Default base image.  This is used for kubectl, helm, and others.
# In some cases, KUBECTL_VERSION can override this; see the 'ansible' 
# container in k8s-tools.yml.  If used, that should match what alpine 
# is providing or it can lead to confusion.
export IMG_ALPINE_K8S?=alpine/k8s:1.30.0

# Ignore any kubeconfig in an environment and start fresh 
define K8S_PROJECT_LOCAL_CLUSTER
$(eval export KUBECONFIG:=${DEFAULT_KUBECONFIG})
$(eval $$(shell umask 066; touch ${KUBECONFIG}))
endef

k8s.scaffold.cluster=$(eval $(call _k8s.scaffold.cluster, ${1}))
define _k8s.scaffold.cluster
ifeq ($${CMK_INTERNAL},1)
$(call log.import.2,skipping (CMK_INTERNAL=1))
else
endif
# Tolerate non-existent kubeconfigs and 
# try to ensure containerized tools can use it
$(call mk.unpack.kwargs, ${1}, template, scaffold_cluster_default)
$(call mk.unpack.kwargs, ${1}, name, scaffold_cluster_default)
$(eval export cluster_args:=$$(shell $${jb} $(strip ${1}) | $${jq} -r .args \
	|| echo "$(if $(filter undefined,$(origin ${kwargs_template}.args)),"",${${kwargs_template}.args})"))

${kwargs_template}.args:=${cluster_args}
clean: stage/cluster.clean ${kwargs_template}.delete/${kwargs_name}
create: stage/cluster.create ${kwargs_template}.get_or_create/${kwargs_name}
endef

k8s.scaffold.minikube=$(call k8s.scaffold.cluster, template=minikube ${1})
k8s.scaffold.kind=$(call k8s.scaffold.cluster, template=kind ${1})
k8s.scaffold.k3d=$(call k8s.scaffold.cluster, template=k3d ${1})


# This reroutes target invocation to a container if necessary, or otherwise 
# executes the target directly.  See the usage example for more info.
#
# USAGE:
#   foo:; $(call containerized.maybe, container_name)
#   .foo:; echo hello-world
.vars.k3d=${io.env}/k3d|awk -F'=' '{print $$1}'|${stream.nl.to.comma}
.vars.minikube=${io.env}/minikube|awk -F'=' '{print $$1}'|${stream.nl.to.comma}
define containerized.maybe
_hdr="${dim}${_GLYPH_IO}${dim} $(shell echo ${@}|sed 's/\/.*//') ${sep}${dim}"\
&& case $${CMK_INTERNAL} in \
	0)  $(call log, $${_hdr} Invoked from top; rerouting to tool-container) \
		; ${trace_maybe} \
		; env="$(strip $(subst ${space},${comma},$(if $(filter undefined,$(origin 2)),,$(2))) )`${.vars.k3d}``${.vars.minikube}`" \
		&& quiet=1 \
		&& _disp=$(strip ${1}).dispatch \
		&& _priv=.$(strip ${@}) \
		&& ([ -z "$${env}" ] && $(call log.trace, $${_hdr} no environment passed) || $(call log.trace, $${_hdr} ${bold}env ${sep} ${green_flow_left}$${env})) \
		&& $(call log, $${_hdr} ${cyan_flow_right}${ital}$${_disp}/$${_priv}) \
		&& ${make} $${_disp}/$${_priv};; \
	*) ${make} .$(strip ${@}) ;; \
esac
endef

k8s-tools.versions: compose.versions/k8s-tools.yml
k8s-tools.versions.table: compose.versions_table/k8s-tools.yml

k8s-tools.versions.show:; ${make} k8s-tools.versions.table | ${stream.glow}
	@#

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'ansible.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-ansible
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# This filter takes the standard JSON output from ansible and cleans it using the assumption
# that this is "localhost"-type ansible for driving tools like eksctl, helm, kubectl, etc.
# Not really intended for remote-controlling hosts with ssh.
ansible.adhoc.filter:='{"changed":.plays[0].tasks[0].hosts.localhost.changed, "module_args": .plays[0].tasks[0].hosts.localhost.invocation.module_args|with_entries(select(.value != null)), "action":.plays[0].tasks[0].hosts.localhost.action, "task":.plays[0].tasks[0].task, "stats":.stats.localhost|with_entries(select(.value != 0))}'
ansible.adhoc.output_filter='{"changed":.plays[0].tasks[0].hosts.localhost.changed, "action":.plays[0].tasks[0].hosts.localhost.action, "task":.plays[0].tasks[0].task, "stats":.stats.localhost|with_entries(select(.value != 0))}|del(.task)'
ansible.adhoc/%:
	@# An interface into the named ansible module.  Just pass the module-arguments.  
	@# Like adhoc ansible, this allows you to call a task without a playbook.
	@# This actually generates a playbook JIT though, which makes things 
	@# more flexible.
	@#
	@# USAGE:
	@#   echo '<arg_json>' | ./compose.mk ansible.adhoc/<ansible_module_name>
	@#
	header="ansible ${sep} ${dim}${*}" \
	&& $(call log.k8s, $${header} ${sep} ${cyan_flow_left}) \
	&& $(io.mktemp) \
	&& ${stream.stdin}  \
	| ${jq} . | ${stream.peek} \
	| ${make} .ansible.gen.playbook/${*} \
	| ${jq} -c . \
	| quiet=1 ${make} ansible.run > $${tmpf} \
	; tmp=`cat $${tmpf} | ${jq} '.plays[0].tasks[].hosts.localhost.failed'` \
	&& case $${tmp} in \
		true) (\
			$(call log, $${header} ${sep} ${red}Task failed:); \
			cat $${tmpf} | ${jq} '.plays[0].tasks[].hosts.localhost' | ${stream.as.log}; \
			$(call log, $${header} ${sep} ${red}Task failed); exit 43); ;; \
		false) ( \
			$(call log.k8s, $${header} ${sep} false ${cyan_flow_right}) \
			&& $(call log.trace, $${header} ${sep} false ${sep} ${cyan_flow_right}) \
			&& cat $${tmpf} | ${jq} ${ansible.adhoc.filter} ); ;; \
		null) ( \
			$(call log.k8s, $${header} ${sep} ${cyan_flow_right}) \
			&& $(call log.trace, $${header} ${sep} null ${sep} ${cyan_flow_right}) \
			&& cat $${tmpf}| ${jq} ${ansible.adhoc.output_filter} ); ;; \
		*) $(call log, ${red}Cannot parse output from ansible.  Empty task?${dim}) \
			; cat "$${tmpf}"|${stream.indent.to.stderr}; exit 77; ;; \
	esac

ansible.blockinfile: ansible.adhoc/blockinfile
	@# Interface for the ansible  block-in-file module[1].
	@# This accepts only module args, but there are several ways to pass them.  
	@# See the docs in ansible.adhoc/<module> for discussion of examples.
	@#
	@# USAGE:
	@#   echo <json_data> | ./k8s.mk ansible.blockinfile
	@#   ./k8s.mk jb <key1>=<val1> <keyn>=<valn> | ./k8s.mk ansible.blockinfile
	@#   data="<key1>=<val1> <keyn>=<valn>" ./k8s.mk ansible.blockinfile
	@#
	@# EXAMPLE:
	@#   path=.gitignore block=".flux.stage.*" | ./k8s.mk ansible.blockinfile
	@#
	@# * `[1]`: https://docs.ansible.com/ansible/latest/collections/ansible/builtin/blockinfile_module.html
    
ansible.helm: ansible.adhoc/kubernetes.core.helm
	@# Interface for the ansible  helm module[1].
	@# This accepts only module args, but there are a few ways to pass them.  
	@# See the docs in 'ansible.adhoc/<module>' for discussion of examples.
	@#
	@# * `[1]`: https://docs.ansible.com/ansible/latest/collections/kubernetes/core/helm_module.html
	@#

ansible.kubernetes.core.k8s k8s.ansible: ansible.adhoc/kubernetes.core.k8s
	@# Interface for the ansible  `kubernetes.core.k8s` module[1].
	@# This accepts only module args, but there are a few ways to pass them.  
	@# See the docs in 'ansible.adhoc/<module>' for discussion of examples.
	@#
	@# * `[1]`: https://docs.ansible.com/ansible/latest/collections/kubernetes/core/k8s_module.html
	@#
.ansible.gen.playbook/%:
	@# Generates a (JSON) playbook object for the given module with the given data.
	@# Optionally takes JSON input, and always produces JSON output.  
	@# Mostly for internal use, see instead the '*.run' public targets.
	@#
	@# USAGE:
	@#   echo "<json>" | ./k8s.mk .ansible.gen.playbook/<ansible_module_name>
	@#
	@# EXAMPLE: 
	@#   echo {} | key=msg val="hello" ./k8s.mk stream.json.append | ./k8s.mk .ansible.gen.playbook/debug
	@#
	${stream.stdin} \
	| ${make} .ansible.gen.task/${*} \
	| printf "`\
		printf '[{"name": "Generated playbook", "hosts": "localhost", "gather_facts": false, "tasks": ['``\
		${stream.stdin} \
		`]}]" \
	| jq .
.ansible.gen.task/%:
		@# Generates a task object for the given module with the given data,
		@# suitable for inserting inside a playbook. Optionally takes JSON input, 
		@# and always produces JSON output. Mostly for internal use, see instead the
		@# '*.run' public targets.
		@#
		@# USAGE: (abstract)
		@#   echo "<json>" | ./k8s.mk .ansible.gen.task/<ansible_module_name>
		@#
		@#
		filter='{"name":"default task","' \
		&& filter="$${filter}${*}\": .}" \
		&& filter="'$${filter}'" \
		&& ([ -p ${stdin} ] && (cat ${stdin}||exit 1) || ${jb} $${data}) \
		| sh -c "jq -c $${filter}"

ansible.run.tasks:
	@# Runs ansible tasks defined by stdin.
	# $(call log.docker, ansible.run.tasks ${sep} ${*}) 
	(${mk.def.read}/ansible.run.tasks.yml \
	&& ${stream.stdin} | ${stream.indent}) \
	| ${make} ansible.run
define ansible.run.tasks.yml
- name: "k8s.mk / ansible.run.tasks"
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
endef

ansible_tasks= ${trace_maybe} && ansible_args="$(if $(filter undefined,$(origin 1)),,$(1))" ${make} ansible.run.def/${@}

ansible.run.def/%:
	@# Like `ansible.run.tasks`, but reads content from given define-block
	@#
	$(call log.k8s, ansible.run.def ${sep} ${*}) 
	${mk.def.read}/${*} | ${stream.peek} | ${make} ansible.run.tasks
	$(call log.k8s, ${@} ${sep} finished)


ansible.run: tux.require
	@# Runs the input-stream as an ansible playbook.
	@# This calls ansible in a way that ensures all output is JSON.
	@#
	@# USAGE:
	@#   cat <playbook> | ./compose.mk ansible.run
	@#
	$(call io.mktemp) \
	&& ${stream.stdin} > $${tmpf} \
	&& ${make} flux.timer/ansible.run/$${tmpf}
# jq.flatten=${jq '[paths(scalars) as $p | {($p | last | tostring): getpath($p)}] | add'


ansible.run/%: .ansible.require
	@# Runs the given playbook file.
	@# This calls ansible in a way that ensures all output is JSON.
	@#
	@# USAGE: 
	@#   ./k8s.mk ansible.run/<path>
	@#
	${trace_maybe} \
	&& ansible_args="$${ansible_args:-} -eansible_python_interpreter=\`which python3\`" \
	&& ansible_args="$${ansible_args} -i localhost, --connection local" \
	&& src="export ANSIBLE_STDOUT_CALLBACK=json && ansible-playbook $${ansible_args} ${*} " \
	&& header="ansible.run ${sep} ${*}" \
	&& $(call log.trace, $${header} ${cyan_flow_right}) \
	&& (case "$${CMK_INTERNAL}" in \
		0) ( \
			${log.trace.target.rerouting}; \
			printf "$${src}\n" | CMK_DEBUG=0 ${make} k8s-tools/ansible/shell/pipe \
			); ;; \
		1) $${src}; ;; \
	esac) \
	|| $(call log.k8s, $${header} ${red}Failed) \

.ansible.require: tux.require 
	@# Alias for 'tux.require'.  We actually just want the dind-base to 
	@# be ready, but this is the simplest way to ensure the bootstrap's 
	@# done.  NB: This is potentially very slow if nothing is cached.

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: argo.* targets
##
## The *`argo.*`* targets describe a small interface for both argo-workflows and argo-events.
##
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-argo
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

argo.list: argo.list/argo 
	@# List for the default namespace (i.e. "argo")

argo.list/%:; $(call containerized.maybe, argo)
	@# Returns the results of 'argo list' for the current argo context.
.argo.list/%:; argo -n ${*} list 

argo.submit.url:
	@# USAGE:
	@#  url="http://../manifest.yml" ./k8s.mk argo.submit.url
	$(call log.k8s, ${@} ${sep} ${cyan_flow_left})
	${io.get.url} && cat $${tmpf} | ${make} argo.submit.stdin

argo.submit.stdin=${make} argo.submit.stdin 
argo.submit.stdin:; $(call containerized.maybe, argo)
	@# USAGE:
	@#  cat manifest.yml | k8s.mk argo.submit.stdin
.argo.submit.stdin:
	$(call log.k8s, ${@} ${sep} ${cyan_flow_left})
	${stream.peek} | ${make} argo.submit/-

argo.submit/%:; $(call containerized.maybe, argo)
	@# Pass the given path to `argo submit`.
	@# This fills in CLI args for `--wait` and `--log` based 
	@# on whether corresponding environment variables are set.
	@# USAGE:
	@#  ./k8s.mk argo.submit/manifest.yml 
.argo.submit/%:
	$(call log.k8s, argo.submit ${sep} ${cyan_flow_left})
	log="--log" \
	&& wait=`[ -z $${wait:-} ] && true || echo "--wait"` \
	&& case ${*} in \
		-) path=/dev/stdin;; \
		*) path=${*};; \
	esac \
	&& set -x && argo submit $${log} $${wait} $${path}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'fission.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-fission
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


_fission.function.assert=\
	fission function list | tail +2 | cut -d' ' -f1 | grep ${1} > /dev/null
fission.function.create/%:; $(call containerized.maybe, fission, fission_code fission_env)
	@# USAGE:
	@#   fission_env=<env_name> 
	@#     fission_code=<path> ./k8s.mk 
	@#      fission.function.create/<fxn_name>
.fission.function.create/%: mk.assert.env/fission_env mk.assert.env/fission_code
	$(call io.log.part1, fission.function.create ${sep} Checking for function @ ${*}) \
	&& ( \
		 $(call _fission.function.assert,${*}) \
		 && $(call io.log.part2, ${dim_green}ok) \
		 || ($(call io.log.part2, ${yellow}not created yet) \
			&& set -x \
			&& fission function create --name ${*} \
				--env $${fission_env} --code $${fission_code}) )


fission.env.list:; $(call containerized.maybe, fission)
	@# Newline-separated list of all the fission environments available.
.fission.env.list:; fission env list
fission.stat:; $(call containerized.maybe, fission)
	@# Describe fission status for the current namespace.
	@# This only writes to stderr, combining the following
	@# commands and failing if any one of them fails:
	@#   fission check
	@#   fission env list
	@#   fission function list
.fission.stat: 
	CMK_INTERNAL=1 ${make} .fission.version | ${stream.as.log}
	$(call log.k8s,fission.stat)
	(  set -x \
		&& fission check \
		&& fission env list && fission function list) \
	| ${stream.as.log}
.fission.version: 
	$(call log.k8s,fission.version)
	fission version | ${yq} -o json

fission.assert.env/%:; $(call containerized.maybe, fission)
	@# Succeeds only when the given environment exists 
	@# for the currently active namespace.  No output.
.fission.assert.env/%:
	fission env list \
		| awk '{print $$1}' \
		| tail -n+2 | grep ${*} 2> /dev/null >/dev/null

fission.env.create/%:; $(call containerized.maybe, fission,img)
	@# Creates the named fission environment if it doesn't already exist.
	@# Desired namespace should already be activated and `img` must be 
	@# set in the environment.
.fission.env.create/%: mk.assert.env/img
	$(call io.log.part1, ${GLYPH_K8S} ${sep} fission.env.create ${sep} ${dim}Checking for environment ${bold}${*})
	${make} fission.assert.env/${*} 2>/dev/null \
	&& $(call io.log.part2, ${no_ansi_dim}already exists) \
	|| ( $(call io.log.part2, ${no_ansi}${yellow}not created yet) \
		&& set -x \
		&& fission env create --name ${*} --image $${img} )

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'terraform.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-terraform
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
terraform_tasks= ${trace_maybe} && terraform_args="$(if $(filter undefined,$(origin 1)),,$(1))" ${make} terraform.run.def/${@}
terraform.run.def/%:
	@# Runs the given define-block as terraform code.
	$(call log.k8s, terraform.run.def ${sep} ${dim_cyan}${*}) 
	${mk.def.read}/${*} | ${make} terraform.run

terraform.run:
	@# Runs the input-stream as terraform.
	@#
	@# USAGE:
	@#   cat <playbook> | ./compose.mk ansible.run
	@#
	suffix=.tf && $(call io.mktemp) \
	&& ${stream.stdin} > $${tmpf} \
	&& ${make} flux.timer/terraform.run/$${tmpf}

terraform.run/%:; $(call containerized.maybe, terraform) 
.terraform.run/%:
	@# Runs the given terraform file.
	@# This creates a temporary directory, and *only* uses the given file.
	${io.mktempd} \
	&& $(call log.k8s, terraform.run ${sep} ${dim}file=${*}) \
	&& cp -rfv ${*} $${tmpd}/main.tf \
	&& ${make} .terraform.run.directory/$${tmpd}

# terraform.run.directory/%:; $(call containerized.maybe, terraform) 
.terraform.run.directory/%:
	@# Runs the given terraform directory (entering it first)
	$(call log.k8s, terraform.run.directory ${sep} ${dim}dir=${*}) \
	&& cd $${tmpd} \
	&& cat *.tf | ${stream.as.log} \
	&& export ZZTF_VAR_KUBECONFIG=$${KUBECONFIG} \
	&& ( terraform init \
		&& terraform apply -auto-approve \
		&& terraform output ) \
	; cd ..

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'kind.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-minikube
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

kind.args?=--wait 0s
kind.cluster.get_or_create/% kind.get_or_create/%:; $(call containerized.maybe, kind)
	@# Create a kind cluster if it does not already exist.
.kind.cluster.get_or_create/% .kind.get_or_create/%:
	$(call log.k8s, kind.cluster.get_or_create ${sep} ${bold}${*})
	${make} flux.do.unless/kind.cluster.create/${*},kind.has_cluster/${*} \
		flux.loop.until/k8s.cluster.ready
kind.delete/% kind.cluster.delete/%:; $(call containerized.maybe, kind)
	@# Deletes the named kind cluster 
.kind.delete/% .kind.cluster.delete/%:
	$(call log.k8s, kind.delete ${sep} ${bold}${*})
	set -x && kind delete cluster --name ${*} #&> /dev/stdout | ${stream.as.log}

kind.has_cluster/%:; $(call containerized.maybe, kind)
	@# Fails unless the given cluster name exists
.kind.has_cluster/%: 
	${make} kind.cluster.list | grep -w ${*} >/dev/null 2>/dev/null
kind.list kind.cluster.list:; $(call containerized.maybe, kind)
	@# Show all known kind clusters
.kind.list .kind.cluster.list:
	data=`kind get clusters` \
	&& echo $${data}
kind.cluster.create/%:; $(call containerized.maybe, kind)
	@# Creates the given cluster unconditionally
.kind.cluster.create/%: io.mkdir/$${MINIKUBE_HOME}
	$(call log.k8s,kind.cluster.create ${sep} ${bold} ${*})
	( set -x \
		&& kind create cluster --name ${*} ${kind.args} $${kind_extra:-} \
			&> /dev/stdout ) \
	| ${stream.as.log}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'minikube.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-minikube
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

minikube.args=
minikube.addons=
minikube.docker_env/%:; $(call containerized.maybe, minikube)
	@# Returns JSON equivalent of `minikube docker-env` output for the given profile.
.minikube.docker_env/%:; 
	minikube -p ${*} docker-env -o json

minikube.cluster.create/%:; $(call containerized.maybe, minikube)
	@# Creates the given cluster unconditionally
.minikube.cluster.create/%: io.mkdir/$${MINIKUBE_HOME}
	$(call log.k8s,minikube.cluster.create ${sep} ${bold} ${*})
	( set -x \
		&& minikube start -p ${*} ${minikube.args} $${minikube_extra:-} \
			&> /dev/stdout ) \
	| ${stream.as.log} \
	&& printf "${minikube.addons}" \
		| ${stream.comma.to.space} | ${stream.space.to.nl} \
		| xargs -I% sh -x -c "minikube -p ${*} addons enable %"

minikube.cluster.get_or_create/% minikube.get_or_create/%:; $(call containerized.maybe, minikube)
	@# Create a minikube cluster if it does not already exist.
.minikube.cluster.get_or_create/% .minikube.get_or_create/%:
	$(call log.k8s, minikube.cluster.get_or_create ${sep} ${bold}${*})
	${make} flux.do.unless/minikube.cluster.create/${*},minikube.has_cluster/${*} \
		flux.loop.until/k8s.cluster.ready

minikube.enable_registry/%:; $(call containerized.maybe, minikube)
	@# Enable minikube's internal registry for the given profile
.minikube.enable_registry/%:
	set -x \
	; minikube addons -p ${*} enable registry \
	; minikube service -p ${*} registry --url
minikube.delete/% minikube.cluster.delete/%:; $(call containerized.maybe, minikube)
	@# Deletes the named minikube cluster 
.minikube.delete/% .minikube.cluster.delete/%: io.mkdir/$${MINIKUBE_HOME}
	$(call log.k8s, minikube.delete ${sep} ${bold}${*})
	minikube delete -p ${*} &> /dev/stdout | ${stream.as.log}


minikube.has_cluster/%:; $(call containerized.maybe, minikube)
	@# Fails unless the given cluster name exists
.minikube.has_cluster/%: 
	${make} minikube.cluster.list | grep -w ${*} >/dev/null 2>/dev/null

minikube.list minikube.cluster.list:; $(call containerized.maybe, minikube)
	@# Show all known minikube clusters
.minikube.list .minikube.cluster.list:
	data=`minikube profile list -o json||echo {}` \
	&& echo $${data} | ${jq} -r '.invalid[].Name' || true \
	&& echo $${data} | ${jq} -r  '.valid[].Name' || true

minikube.purge:; $(call containerized.maybe, minikube)
	@# Purges all known minikube clusters
.minikube.purge:
	${make} minikube.cluster.list | xargs -I% sh -x -c "minikube delete -p %"

minikube.require minikube.running: mk.require.tool/minikube
	@#
	hdr="${@} ${sep}${dim}" \
	&& $(call log.k8s, $${hdr} Checking minikube status) \
	&& ${io.mktemp} \
	&& minikube status -o json | ${jq} . | ${stream.peek} > $${tmpf} \
	&& host=`cat $${tmpf} | ${jq} -re .Host` \
	&& kubelet=`cat $${tmpf} | ${jq} -re .Kubelet` \
	&& server=`cat $${tmpf} | ${jq} -re .APIServer` \
	&& ok="${green}${GLYPH_CHECK}${no_ansi} ok" \
	&& $(call k8s.log.part1, $${hdr}   Host) \
	&& ([ "$${host}" == "Running" ] \
		&& $(call k8s.log.part2, $${ok}) \
		|| ($(call k8s.log.part2, ${red}failed); exit 39)) \
	&& $(call k8s.log.part1, $${hdr}   Kubelet) \
	&& ([ "$${kubelet}" == "Running" ] \
		&& $(call k8s.log.part2, $${ok}) \
		|| ($(call k8s.log.part2, ${red}failed); exit 38)) \
	&& $(call k8s.log.part1, $${hdr}   APIServer) \
	&& ([ "$${server}" == "Running" ] \
		&& $(call k8s.log.part2, $${ok}) \
		|| ($(call k8s.log.part2, ${red}failed); exit 37))

minikube.stat:; $(call containerized.maybe, minikube)
	@# Show status for minikube itself and all known clusters
.minikube.stat: mk.require.tool/minikube
	${make} minikube.cluster.list | ${make} flux.each/minikube.stat


#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'helm.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-helm
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

helm.repo.list: helm.dispatch/.helm.repo.list
	@# Returns JSON for the currently available helm repositories.
.helm.repo.list:; helm repo list -o json

helm.stat:; $(call containerized.maybe, k8s)
	@# Shows the status of things that were installed with helm
	@# This is human friendly output on stderr, use `helm.list` for a JSON dump.
.helm.stat:; ${helm.list} | ${stream.as.log}

helm.list=helm list -A -o json | jq .
helm.list:; $(call containerized.maybe, k8s)
.helm.list:; ${helm.list}
	@# Output of `helm list -A -o json`.
	@# Also available as a macro.

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: 'k3d.* targets
##
## The *`k3d.*`* targets describe a small interface for working with `k3d`[2].  
##
## Mostly just small utilities that can help to keep common tasks idempotent, but
## there's also a TUI that provides a useful overview of what's going on with K3d
##
## DOCS: 
##   [1]: https://robot-wranglers.github.io/k8s-tools/api#api-k3d
##   [2]: https://k3d.io/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Geometry for k3d.commander
GEO_K3D="5b40,111x56,0,0[111x41,0,0{55x41,0,0,1,55x41,56,0[55x16,56,0,2,55x24,56,17,3]},111x14,0,42{55x14,0,42,4,55x14,56,42,5}]"

k3d.purge:; $(call containerized.maybe, k3d)
	@# Deletes all known k3d clusters.
.k3d.purge:
	set -x && k3d cluster delete `${make} k3d.cluster.list | ${stream.nl.to.space}`

k3d.context/%:; $(call containerized.maybe, k3d) 
	@# Sets the given k3d cluster as the active kubectx.
	@# NB: This appends the usual "k3d-" prefix
.k3d.context/%:
	kubectx k3d-${*} \
	; case $$? in \
		0) true;; \
		*) $(call io.log,${red} failed); kubectx;; \
	esac

k3d.cluster.agents/%:
	@# Lists only the agents for the given cluster.
	k3d cluster list -o json \
	| ${jq} '.[]|select(.name=="${*}").nodes[]|select(.role=="agent")'
	
k3d.cluster.create/%:; ${make} flux.timer/.k3d.cluster.create/${*}
	@# Creates a k3d cluster with the given name, using the given configuration.
	@# This supports most of the usual command-line options,
	@# but they must be passed as variables.
	@#
	@# USAGE:
	@#   k3d_servers=.. k3d_agents=.. 
	@#   k3d_port=.. k3d_api_port=.. 
	@#     ./k8s.mk k3d.cluster.create/<cluster_name>
.k3d.cluster.create/%:
	$(call log.k8s, k3d.cluster.create ${sep} ${bold}${*})
	$(call io.mktemp) \
	&& export original=$${KUBECONFIG} \
	&& export KUBECONFIG=$${tmpf} \
	&& export k3d_registry_config=`[ -z "$${k3d_registry_config:-}" ] && true || echo "--registry-config $${k3d_registry_config}"` \
	&& export k3d_config=`[ -z "$${k3d_config:-}" ] && true || echo "--config $${k3d_config}"` \
	&& export k3d_servers=`[ -z "$${k3d_servers:-}" ] && true || echo "--servers $${k3d_servers}"` \
	&& export k3d_agents=`[ -z "$${k3d_agents:-}" ] && true || echo "--agents $${k3d_agents}"` \
	&& sh -x -c "k3d cluster create ${*} \
		$${k3d_config} $${k3d_registry_config} $${k3d_extra} \
		$${k3d_servers} $${k3d_agents} \
		--api-port $${k3d_api_port:-6551} \
		--volume $${tmp}/:/${*}@all --wait" \
	&& k3d kubeconfig merge ${*} --kubeconfig-switch-context --output $${original} >/dev/null \
	&& $(call log.k8s, k3d.cluster.create ${sep} syncing ${dim}$${KUBECONFIG}${no_ansi} -> $${KUBECONFIG_EXTERNAL}) \
	&& k3d kubeconfig merge ${*} --kubeconfig-switch-context --output $${KUBECONFIG_EXTERNAL} >/dev/null

k3d.cluster.delete/%:; $(call containerized.maybe, k3d)
	@# Idempotent version of k3d cluster delete 
	@#
	@# USAGE:
	@#   ./k8s.mk k3d.cluster.delete/<cluster_name>
.k3d.cluster.delete/%:
	$(call log.k8s, ${@} ${sep} Deleting cluster ${sep} ${underline}${*}${no_ansi})
	(set -x && k3d cluster delete ${*}) || true

k3d.cluster.exists/% k3d.has_cluster/%:; $(call containerized.maybe, k3d)
	@# Succeeds iff cluster exists.
.k3d.cluster.exists/% .k3d.has_cluster/%:
	${k3d.cluster.list} | grep -E '(^| )${*}( |$$)'


k3d.cluster.get_or_create/%:; $(call containerized.maybe, k3d)
	@# Create a k3d cluster if it does not already exist.
.k3d.cluster.get_or_create/%:
	$(call log.k8s, k3d.cluster.get_or_create ${sep} ${bold}${*})
	${make} flux.do.unless/k3d.cluster.create/${*},k3d.has_cluster/${*}
k3d.cluster.list k3d.list:; $(call containerized.maybe, k3d)
	@# Returns cluster-names, newline delimited.  Available as a macro.
	@# For more details in a human friendly summary, see `k3d.stat`.
	@# 
	@# USAGE:  
	@#   ./k8s.mk k3d.cluster.list
.k3d.cluster.list .k3d.list:; ${k3d.cluster.list}
k3d.cluster.list=k3d cluster list -o json | ${jq} -r '.[].name' | ${stream.nl.to.space}

k3d.commander:
	@# Starts a 4-pane TUI dashboard, using the commander layout.  
	@# This opens 'lazydocker', 'ktop', and other widgets that are convenient for working with k3d.
	@#
	@# USAGE:  
	@#   KUBECONFIG=.. ./k8s.mk k3d.commander/<namespace>
	@# 
	$(call log.k8s, k3d.commander ${sep} ${no_ansi_dim}Opening commander TUI for k3d)
	geometry="${GEO_K3D}" CMK_INTERNAL=0 ${make} tux.open/flux.loopf/k9s.ui,flux.loopf/k3d.stat

# TUI_CMDR_PANE_COUNT=5 TUX_LAYOUT_CALLBACK=.k3d.commander.layout ${make} tux.commander
# k3d.commander/%:
# 	@# A TUI interface like 'k3d.commander', but additionally sends the given target(s) to the main pane.
# 	@#
# 	@# USAGE:
# 	@#   ./k8s.mk k3d.commander/<target1>,<target2>
# 	@#
# 	export k8s_commander_targets="${*}" && ${make} k3d.commander
# .k3d.commander.layout: .tux.layout.spiral
# 	@# A 5-pane layout for k3d command/control
# 	@#
# 	@# USAGE:  
# 	@#   ./k8s.mk k3d.commander/<namespace>
# 	@# 
# 	$(call log.k8s, ${@} ${sep}${dim} Starting widgets and setting geometry) \
# 	&& geometry="${GEO_K3D}" ${make} .tux.geo.set  \
# 	&& ${make} \
# 		.tux.pane/0/flux.apply/k3d.stat,$${k8s_commander_targets:-io.bash} \
# 		.tux.pane/1/k9s 
# 	tmux send-keys -t 0.3 "sleep 3; entrypoint=bash ${make} k3d/shell" C-m
# 	tmux send-keys -t 0.4 "CMK_DEBUG=0 interval=10 ${make} flux.loopf/k8s.cluster.wait" C-m
# 	# WARNING: can't use .tux.pane/... here, not sure why 
# 	${make} .tux.widget.lazydocker/2/k3d

k3d.help:; ${make} mk.namespace.filter/k3d.
	@# Shows targets for just the 'k3d' namespace.

k3d.panic:; $(call containerized.maybe, k3d)
	@# Non-graceful stop for everything that is k3d related. 
	@# 
	@# USAGE:  
	@#   ./k8s.mk k3d.panic
.k3d.panic:
	$(call log.k8s, ${@} ${sep} Stopping all k3d containers)
	${k3d.cluster.list} | ${flux.each}/k3d.cluster.delete

k3d.stat:; $(call containerized.maybe, k3d)
	@# Show status for k3d.
	${make} k3d.ps | ${jq} -r .Name | ${stream.indent} | ${stream.as.log}
.k3d.stat:
	$(call log.k8s, k3d.stat)
	( printf "Versions:\n" \
	  && k3d --version | ${stream.indent} \
	  && printf "Clusters:" \
	  && ${make} k3d.cluster.list | ${stream.indent} ) \
	| ${stream.as.log}

# k3d.stat.widget:
# 	clear=1 verbose=1 interval=10 ${make} flux.loopf/flux.apply/k3d.stat

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'k8s.*' targets
##
## This is the default target-namespace for `k8s.mk`.  It covers general 
## helpers, and should be safe to use from the docker host even if tools like 
## kubectl are not available.
##
## DOCS: 
##   * [1] https://robot-wranglers.github.io/k8s-tools/api#api-k8s
##   * [2] https://kubernetes.io/docs/reference/using-api/server-side-apply/
##
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

k8s.pod.shell/%:
	@# This drops into a debugging shell for the named pod using `kubectl exec`,
	@# plus a streaming version of the same which allows for working with pipes.
	@#
	@# NB: This target assumes that the named pod actually exists.  If you want
	@# an idempotent create-operation for such a pod.. see `k8s.test_harness`.
	@#
	@# NB: This target attempts to be "universal", so that it may run from the 
	@# docker host or inside the `k8s:base` container.  This works by detecting 
	@# aspects of the caller context.  In general, it tries to use k8s-tools.yml 
	@# when that makes sense and if it's present, falling back to kubectl.
	@#
	@# If `user` is set as an environment variable, this tries to use `su` to overcome 
	@# the fact that `kubectl exec --user` does no work like `docker exec --user`.
	@# See also: https://github.com/kubernetes/kubernetes/issues/30656
	@#
	@# USAGE: Interactive shell in pod:
	@#   ./k8s.mk k8s.shell/<namespace>/<pod_name>
	@#	
	namespace=`echo ${*}|cut -d/ -f1` \
	&& pod_name=`echo ${*}|cut -d/ -f2` \
	&& case $${user:-} in \
		"") ishell=bash;; \
		*) ishell="su - $${user} -s bash";; \
	esac \
	&& set -x \
	&& script="kubectl exec \
		-n $${namespace} -it $${pod_name} -- $${ishell}" \
	&& docker compose -f ${K8S_TOOLS} run -it -e CMK_INTERNAL=1 k8s sh -x -c "$${script}"

kubectl.pod.shell/%:
	namespace=`echo ${*}|cut -d/ -f1` \
	&& pod_name=`echo ${*}|cut -d/ -f2` \
	&& case $${user:-} in \
		"") ishell=bash;; \
		*) ishell="su - $${user} -s bash";; \
	esac \
	&& set -x \
	&& kubectl exec \
		-n $${namespace} -it $${pod_name} -- $${ishell}

# k8s.get/% kubectl.get/%:; $(call containerized.maybe, k8s)
# .k8s.get/% .kubectl.get/%:
# 	@# Returns resources under the given namespace, for the given kind.
# 	@# This can also be used with a 'jq' query to grab deeply nested results.
# 	@# Pipe Friendly: results are always JSON.  Caller should handle errors.
# 	@#
# 	@# USAGE: 
# 	@#	 ./k8s.mk kubectl.get/<namespace>/<kind>/<resource_name>/<jq_filter>
# 	@#
# 	@# Argument for 'kind' must be provided, but may be "all".  
# 	@# Argument for 'filter' is optional.
# 	@#
# 	$(eval export pathcomp:=$(shell echo ${*}| sed -e 's/\// /g'))
# 	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}')))
# 	$(eval export kind:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}')))
# 	$(eval export name:=$(strip $(shell echo ${*} | awk -F/ '{print $$3}')))
# 	$(eval export filter:=$(strip $(shell echo ${*} | awk -F/ '{print $$4}')))
# 	export cmd_t="kubectl get $${kind} $${name} -n $${namespace} -o json | jq -r $${filter}" \
# 	&& $(call log.k8s, kubectl.get${no_ansi_dim} // $${cmd_t}) \
# 	&& eval $${cmd_t}

k8s.namespace.purge.by.prefix/%:
	@# Runs a separate purge for every matching namespace.
	@# NB: This isn't likely to clean everything, see the docs for your dependencies.
	@#
	@# USAGE: 
	@#    ./k8s.mk k8s.namespace.purge.by.prefix/<prefix>
	@#
	${make} kubectl.namespace.list \
	| grep ${*} | ${stream.peek} \
	| xargs -I% bash -x -c "${make} k8s.namespace.purge/%"
	|| $(call log.k8s, ${@} ${sep} ${dim}Nothing to purge: no namespaces matching \`${*}*\`)

k8s.graph/%:
	@# Graphs resources under the given namespace, for the given kind, in dot-format.
	@# Pipe Friendly: results are always dot files.  Caller should handle any errors.
	@#
	@# This requires the krew plugin "graph" (installed by default with k8s-tools.yml).
	@#
	@# USAGE: 
	@#	 ./k8s.mk k8s.graph/<namespace>/<kind>
	@#	 ./k8s.mk k8s.graph/<namespace>/<kind>,<outfile>
	@#
	@# Argument for 'kind' must be provided, but may be "all".  
	@#
	${make} k8s.dispatch/.k8s.graph/${*}
.k8s.graph/%:
	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}')))
	$(eval export kind:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}')))
	export scope=`[ "$${namespace}" == "all" ] && echo "--all-namespaces" || echo "-n $${namespace}"` \
	&& export KUBECTL_NO_STDERR_LOGS=1 \
	&& kubectl graph $${kind:-pods} $${scope}

k8s.graph: k8s.graph/all/pods 
	@# Alias for k8s.graph/all/pods.  This returns dot-format data.

k8s.graph.tui: k8s.graph.tui/all/pods
	@# Alias for 'k8s.graph.tui/all/pods'.  This prints a visual graph on the terminal.

# k8s.graph.tui.loop: k8s.graph.tui.loop/kube-system/pods
# 	@# Loops the graph for the kube-system namespace
# k8s.graph.tui.loop/%:
# 	@# Display an updating, low-resolution image of the given namespace topology.
# 	@#
# 	@# USAGE:  
# 	@#   ./k8s.mk k8s.graph.tui.loop/<namespace>
# 	@# 
# 	failure_msg="${yellow}Waiting for cluster to get ready..${no_ansi}" \
# 	${make} flux.loopf/k8s.graph.tui/${*}

k8s.graph.tui/%:
	@# Previews topology for a given kubernetes <namespace>/<kind> in a way that is terminal-friendly.
	@#
	@# This is a human-friendly way to visualize progress or changes, because it supports 
	@# very large input data from complex deployments with lots of services/pods, either in 
	@# one namespace or across the whole cluster. To do that, it has to throw away some 
	@# information compared with raw kubectl output, and node labels on the graph aren't 
	@# visible.
	@#
	@# This is basically a pipeline from graphs in dot format, generated by kubectl-graph, 
	@# then passed through some image-magick transformations, and then pushed into 
	@# the 'chafa' tool for generating ASCII-art from images.
	@#
	@# USAGE: (same as k8s.graph)
	@#   ./k8s.mk k8s.graph.tui/<namespace>/<kind>
	@#   ./k8s.mk k8s.graph.tui/<namespace>/<kind>,<outfile>
	@#
	quiet=1 ${make} k8s.dispatch/.k8s.graph.tui/${*} \
	| quiet=1 size=${io.term.width} ${make} tui.dispatch/..k8s.graph.tui | ${stream.img}
.k8s.graph.tui/%:
	@# (Private helper for k8s.graph.tui)
	@#
	$(call io.mktemp) && ${trace_maybe} \
	&& namespace=`printf ${*}|cut -d/ -f1` \
	&& outfile=`printf ${*}|cut -s -d, -f2-` \
	&& outfile="$${outfile:-/tmp/png.png}" \
	&& ${make} .k8s.graph/$${namespace} 2>/dev/null > $${tmpf} \
	&& cat $${tmpf} 
..k8s.graph.tui:
	outfile="$${outfile:-/tmp/png.png}" \
	&& ${stream.stdin}	| dot /dev/stdin -Tsvg -o /tmp/svg.svg \
			-Gbgcolor=transparent -Gsize=200,200 \
			-Estyle=bold -Ecolor=red -Eweight=150 2> /dev/null \
		&& convert /tmp/svg.svg -transparent white -background transparent -flatten png:- 2>/dev/null
.k8s.graph.tui.clear/%:; clear="--clear" ${make} .k8s.graph.tui/${*}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
kubectx=`kubectx -c`

k8s.help: mk.namespace.filter/k8s.
	@# Shows targets for just the 'k8s' namespace.

k8s.kubens/%: 
	@# Context-manager.  Activates the given namespace.
	@# NB: This modifies state in the kubeconfig, so that it can effect contexts 
	@# outside of the current process, and therefore this is not thread-safe.
	@#
	@# USAGE:  
	@#   ./k8s.mk k8s.kubens/<namespace>
	@#
	$(call log.k8s, k8s.kubens ${sep} ${dim}${*}) \
	&& TERM=xterm kubens ${*} 2>&1 | ${stream.as.log}

k8s.kubens.create/%:; ${make} kubectl.namespace.create/${*} k8s.kubens/${*}
	@# Context-manager.  Activates the given namespace, creating it first if necessary.
	@#
	@# NB: This modifies state in the kubeconfig, so that it can effect contexts 
	@# outside of the current process, therefore this is not thread-safe.
	@#
	@# USAGE: 
	@#    ./k8s.mk k8s.kubens.create/<namespace>
	
k8s.namespace/%:; ${make} k8s.kubens/${*}
	@# Context-manager.  Activates the given namespace.
	@#
	@# NB: This modifies state in the kubeconfig, so that it can effect contexts 
	@# outside of the current process, therefore this is not thread-safe.
	@#
	@# USAGE:  
	@#	 ./k8s.mk k8s.namespace/<namespace>

k8s.namespace.label/%:
	@# Appends the given label to the given namespace.
	@#
	@# USAGE: 
	@#   key=<key> val=<val> ./k8s.mk k8s.namespace.label/<namespace>
	@#   ./k8s.mk k8s.namespace.label/<namespace>/<key>/<val>
	@#
	true \
	&& ns=`echo ${*} | cut -d/ -f1` \
	&& key=$${key:-`echo ${*}|cut -s -d/ -f2`} \
	&& val=$${val:-`echo ${*}|cut -s -d/ -f3`} \
	&& ( printf '{ "state": "patched", "kind": "Namespace", "name": "' \
	; printf "$${ns}"; printf '", "definition": {"metadata": {"labels": {' \
	; printf "\"$${key}\": \"$${val}\"}}}}") | ${jq} . \
	| ${make} k8s.ansible

k8s.namespace.purge/%:; $(call containerized.maybe, k8s)
	@# Wipes everything inside the given namespace.
	@#
	@# USAGE: 
	@#    k8s.namespace.purge/<namespace>
.k8s.namespace.purge/%:
	$(call log.k8s, k8s.namespace.purge ${sep} ${no_ansi}${green}${*} ${sep} Waiting for delete (cascade=foreground))
	${trace_maybe} \
	&& kubectl delete namespace --cascade=foreground ${*} -v=9 2>/dev/null || true

k8s.jobs.wait: k8s.jobs.wait/all
	@# Wait for all jobs in all namespaces
k8s.jobs.wait/%:; $(call containerized.maybe, k8s)
	@# Wait for all jobs in the given namespace
.k8s.jobs.wait/%:; ${make} kubectl.jobs.wait/${*}

k8s.pods.wait: k8s.pods.wait/all
	@# Wait for all pods in all namespaces
k8s.pods.wait/%:; $(call containerized.maybe, k8s)
	@# Wait for all pods in the given namespace
.k8s.pods.wait/%:; ${make} kubectl.pods.wait/${*}

k8s.namespace.wait: k8s.namespace.wait/all
	@# Wait for all pods in all namespaces
k8s.namespace.wait/%:; $(call containerized.maybe, k8s)
	@# Waits for every pod/job in the given namespace to be ready.
	@#
	@# This uses only kubectl/jq to loop on pod-status, but assumes that 
	@# the krew-plugin 'sick-pods'[1] is available for formatting the 
	@# user-message.  See `k8s.wait` for an alias that waits on all pods.
	@#
	@# NB: If the parameter is "all" then this uses --all-namespaces
	@#
	@# USAGE: 
	@#   ./k8s.mk k8s.namespace.wait/<namespace>
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/alecjacobs5401/kubectl-sick-pods
.k8s.namespace.wait/%:
	${make} kubectl.namespace.wait/${*} kubectl.jobs.wait/${*}

.wait_cmd="gum \
	spin --spinner $${spinner:-jump} \
	--spinner.foreground=$${color:-39} \
	--title=\"Waiting ${K8S_POLL_DELTA}s\" \
	-- sleep ${K8S_POLL_DELTA}"
.k8s.namespace.pending/%:
	${set_scope} \
	&& header="k8s.namespace.pending ${sep} ${dim}ctx=${dim_cyan}${kubectx} ${sep} ${green}${*}${no_ansi}" \
	&& $(call log.k8s, $${header} ${sep}${dim} Looking for pods in phase=pending)
	&& until \
		kubectl get pods $${scope} -o json 2> /dev/null \
		| jq '${.filter.pending}' 2> /dev/null \
		| jq '.[] | halt_error(length)' 2> /dev/null \
	; do \
		${.sick.pods} && eval "${.wait_cmd}"; \
	done \

set_scope=scope=`[ "${*}" == "all" ] && echo "--all-namespaces" || echo "-n ${*}"`
.format.header=awk 'NR==1{print "${dim_cyan}${bold}" $$0 "${no_ansi_dim}";next}{print $$0}'
k8s.pods k8s.pods.all: k8s.pods/all
	@# Returns information about pods in all namespaces.  
	@# Not for parsing; this info is human friendly, and output to logging channel.
k8s.pods/%:; $(call containerized.maybe, k8s)
	@# Shows pods for the given namespace, excluding ones with "completed" status.
	@# Not for parsing; this info is human friendly, and output to logging channel.
.k8s.pods/%:; ${make} kubectl.pods/${*}
# k8s.pods.watch:; entrypoint=watch cmd="-n1 kubectl get po -A" ${make} k8s

k8s.svc/%:; $(call containerized.maybe, k8s)
	@# Shows services for the given namespace
	@# Not for parsing; this info is human friendly, and output to logging channel.
.k8s.svc/%:; ${make} kubectl.svc/${*}

k8s.deployments/%:; $(call containerized.maybe, k8s)
	@# Shows deployments for the given namespace
	@# Not for parsing; this info is human friendly, and output to logging channel.
.k8s.deployments/%:; ${make} kubectl.deployments/${*}

k8s.ready k8s.cluster.ready:; $(call containerized.maybe, k8s)
	@# Checks whether the cluster is available.  
	@# This just returns the exit status of cluster-info, and not 
	@# whether pods are all in a ready state. For that, see 'k8s.wait'
	@#
	@# EXAMPLE: 
	@#   ./k8s.mk k8s.cluster.ready
	@#
	@# EXAMPLE: ( in a loop )
	@#   ./k8s.mk flux.loop.until/k8s.cluster.ready
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/alecjacobs5401/kubectl-sick-pods
.k8s.ready .k8s.cluster.ready:
	hdr="k8s.cluster.ready ${sep} ctx=${dim_cyan}${kubectx} ${sep}" \
	&& kubectl cluster-info > /dev/null 2>&1 \
	; case $$? in \
		0) $(call log.k8s, $${hdr} Cluster connectivity ok); exit 0; ;; \
		*) $(call log.k8s, $${hdr} Failed to connect to the cluster); exit 1; ;; \
	esac

k8s.stat:; $(call containerized.maybe, k8s)
.k8s.stat:
	@# Describes status for cluster, cluster auth, and namespaces.
	@# Not pipe friendly, and not suitable for parsing!  
	@#
	@# This is just for user information, as it's generated from 
	@# a bunch of tools that are using very different output styles.
	@#
	@# For a shorter, looping version that is suitable as a tmux widget, see 'k8s.stat.widget'
	@#
	tmp1=`kubectx -c||true` && tmp2=`kubens -c || true` \
		&& $(call log.k8s, k8s.stat ${no_ansi_dim}ctx=${green}${underline}$${tmp1}${no_ansi_dim} ns=${green}${underline}$${tmp2}) \
		&& ${make} k8s.stat.env kubectl.cluster.stat \
			kubectl.get.nodes kubectl.stat.auth  \
			k8s.stat.ns kubectl.kubectx;

k8s.test_harness.random:; ${make} k8s.test_harness/default/`uuidgen`
	@# Starts a test-pod with a random name in the given namespace, optionally blocking until it's ready.
	@#
	@# USAGE: 
	@#	`k8s.test_harness.random`

k8s.test_harness/%:; $(call containerized.maybe, k8s,wait interactive img)
	@# Starts a test-pod in the given namespace, optionally blocking 
	@# until it's ready. If `img` is provided in environment it will 
	@# be used, otherwise defaults to 'IMG_ALPINE_K8S'.
	@#
	@# USAGE: 
	@#	`k8s.test_harness/<namespace>/<pod_name>`
	@#
define .k8s.test_harness.manifest
{ 
"apiVersion": "v1", "kind":"Pod", 
"metadata":{"name": "__REPLACED__"}, 
"spec":{ 
	"containers": [ {
		"name": "__REPLACED__-container", 
		"tty": true, "stdin": true,
		"image": "__REPLACED__", 
		"command": ["sleep", "infinity"] } ] } 
}
endef
.k8s.test_harness/%:
	namespace="`echo ${*} | cut -d/ -f1`" \
	&& name="`echo ${*} | cut -d/ -f2-`" \
	&& case $${name} in \
		"") name=`uuidgen`;; \
	esac \
	&& img=$${img:-$${IMG_ALPINE_K8S}} \
	&& hdr="k8s.test_harness ${sep} ns=${dim_cyan}$${namespace} ${sep}${dim}" \
	&& $(call log.k8s,$${hdr} Launching ${ital}$${img} as ${bold}$${name}) \
	&& ${mk.def.read}/.k8s.test_harness.manifest \
	| ${jq} ".metadata.name = \"$${name}\"" \
	| ${jq} ".spec.containers[0].name = \"$${name}-container\"" \
	| ${jq} ".spec.containers[0].image = \"$${img}\"" \
	| ${stream.peek} \
	| kubectl apply --namespace $${namespace} -f - \
	| ${stream.as.log} \
	&& case "$${wait:-}$${interactive:-}" in \
		"") true;; \
		*) $(call log.k8s,$${hdr} Waiting for namespace to become ready..) \
			&& ${make} kubectl.pods.wait/$${namespace};; \
	esac \
	&& case "$${interactive:-}" in \
		"") true;; \
		*) ${make} kubectl.pod.shell/$${namespace}/$${name};; \
	esac

k8s.wait k8s.cluster.wait: k8s.namespace.wait k8s.jobs.wait
	@# Waits until all pods in all namespaces are ready.  (Alias for 'k8s.namespace.wait/all')
# k8s.wait.quiet/%:; ${make} k8s.jobs.wait/${*} k8s.pods.wait/${*}
k8s.stat.env:
	@# Shows cluster, kube, and docker environment variables
	@#
	$(call log.k8s, ${@} ) 
	(   (env | grep CLUSTER || true) \
	  ; (env | grep KUBE    || true) \
	  ; (env | grep DOCKER  || true) \
	) #| ${stream.grep.safe} | ${stream.indent} 

k8s.stat.ns:
	@# Shows all namespaces for the current cluster.
	@# (This is just the output of `kubens` with no arguments)
	$(call log.k8s, ${@} ${sep} ${dim}Listing namespaces)
	kubens | ${stream.indent} 

k8s.kubectx: k8s.dispatch.quiet/kubectl.kubectx
	@# Returns `kubectx` result
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'kubetail.*' targets
##
## Note that kubetail doesnt honor KUBECONFIG in environment, therefore 
## all targets must reference file specifically. See the related issue `[2]`
## 
## DOCS: 
##  `[1]`: https://robot-wranglers.github.io/k8s-tools/api#api-kubectl
##  `[2]`: https://github.com/kubetail-org/kubetail/issues/225
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# kubetail/%:; $(call containerized.maybe, k8s)
# 	@# Runs `kubetail logs` with the given argument
# 	kubetail --kubeconfig $${KUBECONFIG} logs ${*}
kubetail/%:; $(call containerized.maybe, k8s)
	@# USAGE:
	@#   kubetail.logs/<namespace>/<kind>/<filter>
	@#   kubetail.logs/fission/deployments/*
	@#   kubetail.logs/fission/deployments/*,fission/pods/*
.kubetail/%:
	case ${*} in \
		*,*) cmd="`printf "${*}" \
			| ${stream.comma.to.nl} \
			| xargs -I% echo ..kubetail/% | ${stream.nl.to.space}`";; \
		*) cmd="..kubetail/${*}";; \
	esac \
	&& ${make} $${cmd}
..kubetail/%:
	scope="`echo ${*} | cut -d/ -f1`" \
	&& kind="`echo ${*} | cut -d/ -f2`" \
	&& rest="`echo ${*} | cut -d/ -f3-| sed 's/all$$/*/'`"  \
	&& $(call log.k8s, kubetail.logs ${sep} ${dim_cyan}$${scope} ${sep} ${dim}kind=${bold}$${kind} ${no_ansi_dim}filter=${ital}$${rest}) \
	&& kubetail --kubeconfig $${KUBECONFIG} logs $${scope}:$${kind}/$${rest} |${jq} . | ${stream.as.log}

kubetail.serve: kubetail_server.up
kubetail.serve.bg: kubetail_server.up.detach
# .kubetail.serve:
# 	set -x && kubetail serve --skip-open \
# 		--kubeconfig $${KUBECONFIG} \
# 		--port 9999 --host 0.0.0.0 
# kubetail.serve.detach: k8s.exec.detach/.kubetail.serve

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'kubectl.*' private targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-kubectl
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
kubectl.quiet=>(grep -v "missing the kubectl.kubernetes.io/last-applied-configuration annotation")
_kubectl.apply=kubectl apply \
		`[ -z "$${server_side:-}" ] && echo "" || echo "--force-conflicts --server-side"` \
		-f ${1} 2> ${kubectl.quiet}
kubectl.apply/%:
	@# Runs kubectl apply on the given file,
	@# Also available as a macro.
	$(call _kubectl.apply, ${*})
kubectl.apply=${make} kubectl.apply

kubectl.apply.stdin:
	@# Equivalent to `kubectl apply -f -` but additionally implies
	@# a preview of the applied file, which is sent to stderr.
	@#
	$(call log.k8s, ${@} ${sep} ${cyan_flow_left})
	${kubectl.apply.stdin}
stream.kubectl.apply=${kubectl.apply.stdin}
kubectl.apply.stdin= \
	${stream.stdin} \
		| ${stream.peek} \
		| $(call _kubectl.apply, -)

kubectl.apply.url:; ${io.get.url} && ${make} kubectl.apply/$${tmpf} | ${stream.as.log}
	@# Apply URL.  Rather than handing the URL directly to kubectl, 
	@# this  downloads the file first and applies as usual for
	@# simple previews. Also available as a macro.
kubectl.apply.url=${make} kubectl.apply.url

kubectl.cluster.stat:
	@# Shows cluster status.
	@#
	$(call log.k8s, ${@} ${sep}${no_ansi_dim} Showing cluster status..)
	kubectl version -o json 2>/dev/null | jq . || true
	kubectl cluster-info -o json 2>/dev/null  | jq . || true

_kubectl.create=kubectl create -f ${1}
kubectl.create/%:
	@# Interface for kubectl create.
	$(call _kubectl.create, ${*}) 2> >(grep -v 'already exists$$') \
	; result=$$? \
	&& strict=$${strict:-1} \
	&& case $${result} in \
		0) true;; \
		*) case $${strict} in \
			0) $(call log.k8s, ${yellow}kubectl.create${dim} failed but strict=$${strict} and partial updates are allowed);; \
			*) exit $${result};; \
			esac;; \
	esac

kubectl.create.stdin:; $(call _kubectl.create, -)
	@# Like `kubectl.create`, but accepts file-input on stdin
kubectl.create.url:; ${io.get.url} && ${make} kubectl.create/$${tmpf}
	@# Like `kubectl.create`, but expects that `url` is set in environment.


kubectl.get.pod_names:; kubectl get pods -o=jsonpath='{.items[*].metadata.name}'
kubectl.get.nodes:
	@# Status for nodes. 
	@# Not machine-friendly.  See instead 'kubectl.get'.
	@#
	node_count=`kubectl get nodes -oname|wc -l` \
	&& $(call log.k8s, ${@} (${no_ansi}${green}$${node_count}${no_ansi_dim} total))
	kubectl get nodes

kubectl.exec.pipe/%:
	@# Stream commands into the named pod.
	@#
	@# USAGE: 
	@#   echo uname -a | ./k8s.mk k8s.shell/<namespace>/<pod_name>/pipe
	@#
	namespace=$(shell echo ${*}|awk -F/ '{print $$1}') \
	&& pod_name=$(shell echo ${*}|awk -F/ '{print $$2}') \
	&& ${stream.stdin} | docker compose -f ${K8S_TOOLS} run -T k8s \
		sh -x -c "KUBECONFIG=${KUBECONFIG} kubectl exec -n $${namespace} -i $${pod_name} -- bash"

kubectl.kubectx:
	@# Displays output of kubectx to stderr.
	$(call log.k8s, ${@} ${sep} ${no_ansi_dim}Showing cluster context)
	kubectx | ${stream.indent} 

kubectl.wait: kubectl.jobs.wait/all kubectl.namespace.wait/all 
	@# Wait for all pods and all jobs in all namespaces to finish

kubectl.jobs.wait: kubectl.jobs.wait/all
	@# Wait for all jobs in all namespaces to finish
kubectl.pods.wait: kubectl.pods.wait/all
	@# Wait for all pods in all namespaces to finish


kubectl.pods.wait/%:
	@# Wait for all jobs to finish inside the given namespace
	${set_scope} \
	&& header="k8s.pods.wait ${sep} ${dim}ctx=${dim_cyan}${kubectx} ${sep} ${dim}ns=${dim_cyan}${*}${no_ansi}" \
	&& $(call k8s.log.part1, $${header} ${sep}${dim} Looking for pending pods) \
	&& pod_count=`kubectl get pods $${scope} --no-headers 2>/dev/null| ${stream.count.lines}` \
	&& case $${pod_count} in \
		0) $(call k8s.log.part2,${GLYPH_CHECK} No pods found); exit 0;; \
		*) $(call k8s.log.part2,$${pod_count});; \
	esac \
	&& (kubectl wait $${scope} \
		--for=condition=Ready pod \
		--all --timeout=9999s | ${stream.as.log} )\
	|| \
		($(call k8s.log,$${header}Timeout or interrupt ${sep} ${no_ansi} Pods not ready) \
			&& kubectl get pods $${scope} -o wide | ${stream.as.log} && exit 1) \
	&& failed_pods=$$(\
		kubectl get pods $${scope} --no-headers 2>/dev/null \
		| grep -E 'CrashLoopBackOff|ErrImagePull|ImagePullBackOff|CreateContainerConfigError|RunContainerError|InvalidImageName|Error|Failed' || true ) \
	&& $(call k8s.log.part1, $${header} ${sep}${dim} Status) \
	&& case "$${failed_pods}" in \
		"") $(call k8s.log.part2,${GLYPH_CHECK} Ready);; \
		*) $(call k8s.log.part2,Not Ready); kubectl describe pods $${scope}; exit 1;; \
	esac
kubectl.jobs.wait/%:
	@# Wait for all jobs to finish inside the given namespace
	${set_scope} \
	&& hdr="k8s.jobs.wait ${sep} ${dim}ctx=${dim_cyan}${kubectx} ${sep} ${dim}ns=${dim_cyan}${*}${no_ansi}" \
	&& $(call k8s.log.part1, $${hdr} ${sep}${dim} looking for unfinished jobs) \
	&& data="`kubectl get jobs $${scope} --no-headers=true 2>/dev/null`" \
	&& count="`printf "$${data}" | ${stream.count.lines}`" \
	&& [ -z "$${data}" ] \
		&& $(call k8s.log.part2, ${GLYPH_CHECK} None found) \
		|| ( \
			$(call k8s.log.part2, ${yellow}$${count}) \
			&& printf "$${data}" \
			| ${stream.peek} | awk '{print $$1}' \
			| ${io.xargs} "\
				kubectl wait $${scope} --for=condition=complete job/%" \
			| ${stream.as.log})
kubectl.namespace.wait/%:
	@# FIXME: use ${set_scope}
	${set_scope} \
	&& header="k8s.namespace.wait ${sep} ${dim}ctx=${dim_cyan}${kubectx} ${sep} ${dim}ns=${dim_cyan}${*}${no_ansi}" \
	&& $(call log.k8s, $${header} ${sep}${dim} Looking for pods in state=waiting) \
	&& until \
		kubectl get pods $${scope} -o json 2> /dev/null \
		| jq '${.filter.waiting}' 2> /dev/null \
		| jq '.[] | halt_error(length)' 2> /dev/null \
	; do \
		${.sick.pods} \
		&& $(call log, $${header} ${sep}${dim} ${io.timestamp} ${sep} ${bold}Pods not ready yet)\
		&& eval ${.wait_cmd}; \
	done \
	&& $(call log.k8s, $${header} ${sep}${dim} ${io.timestamp} ${sep} No pods waiting ${GLYPH_SPARKLE}) \
	&& ${make} kubectl.pods/${*} \
	&& case $${strict:-0} in \
		0) true;; \
		*) ${make} .k8s.namespace.pending/${*} ;; \
	esac
.filter.waiting=[.items[].status.containerStatuses[]|select(.state.waiting)]
.filter.pending=[.items[].status.containerStatuses[]|select(.state.pending)]
define .sick.pods 
kubectl sick-pods $${scope} 2>&1 \
	| sed 's/^[ \t]*//'\
	| sed "s/FailedMount/$(shell printf "${yellow}Failed${no_ansi}")/g" \
	| sed "s/streaming log results:/streaming log results:\n\t/g" \
	| sed "s/is not ready! Reason Provided: None/$(shell printf "${bold}not ready!${no_ansi}")/g" \
	| sed 's/ in pod /\n\t\tin pod /g' \
	| sed -E 's/assigned (.*) to (.*)$$/assigned \1/g' \
	| sed "s/Failed\n\n/$(shell printf "${yellow}Failed${no_ansi}")/g" \
	| sed "s/Scheduled/$(shell printf "${yellow}Scheduled${no_ansi}")/g" \
	| sed "s/Pulling/$(shell printf "${green}Pulling${no_ansi}")/g" \
	| sed "s/Warning/$(shell printf "${yellow}Warning${no_ansi}")/g" \
	| sed "s/Pod Conditions:/$(shell printf "☂${dim_green}${underline}Pod Conditions:${no_ansi}")/g" \
	| sed "s/Pod Events:/$(shell printf "${underline}${dim_green}Pod Events:${no_ansi}")/g" \
	| sed "s/Container Logs:/$(shell printf "${underline}${dim_green}Container Logs:${no_ansi}")/g" \
	| sed "s/ContainerCreating/$(shell printf "${green}ContainerCreating${no_ansi}")/g" \
	| sed "s/ErrImagePull/$(shell printf "${yellow}ErrImagePull${no_ansi}")/g" \
	| sed "s/ImagePullBackOff/$(shell printf "${yellow}ImagePullBackOff${no_ansi}")/g" \
	| sed ':a;N;$$!ba;s/\n\n/\n/g' \
	| tr '☂' '\n' 2>/dev/null | ${stream.dim} > ${stderr} \
&& printf '\n'>/dev/stderr 
endef
k8s.get.svc/%:; $(call containerized.maybe, k8s)
	@#
	@# USAGE:
	@#   k8s.get.svc/<ns>/<name>/<filter>
	@#   k8s.get.svc/ab-testing/coin-service/.spec.clusterIP
.k8s.get.svc/%:; ${make} kubectl.get.svc/${*}

kubectl.get=kubectl get $${kind} -n $${ns} $${id} -o json | ${jq} -re $${jsonpath}
kubectl.get.svc/%:
	@#
	@# USAGE:
	@#   kubectl.get.svc/<ns>/<name>/<filter>
	@#   kubectl.get.svc/ab-testing/coin-service/.spec.clusterIP
	@#
	ns=`echo ${*}|cut -d/ -f1` \
	&& id=`echo ${*}|cut -d/ -f2` \
	&& jsonpath=`echo ${*}|cut -d/ -f3-` \
	&& kind=svc && ${kubectl.get}
kubectl.namespace.create/%:
	@# Idempotent version of namespace-create.
	@#
	@# USAGE: 
	@#    kubectl.namespace.create/<namespace>
	@#
	$(call log.k8s, kubectl.namespace.create ${sep} ${bold}${*})
	server_side=1 \
	&& kubectl create namespace ${*} --dry-run=client -o yaml \
		| ${stream.peek} | $(call _kubectl.apply, -)

kubectl.namespace.list:
	@# Returns all namespaces in a simple array.
	@# NB: Must remain suitable for use with `xargs`!
	@#
	kubectl get namespaces -o json \
		| ${jq} -r '.items[].metadata.name'

kubectl.pods/%:
	@# Show deployments in the given namespace
	kind=pod \
	kubectl_extra="\
		--field-selector=status.phase!=Completed \
		-o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[*].restartCount" \
	${make} kubectl.show/${*}

kubectl.show/%:
	@# Show the given types in the given namespace
	$(call log.k8s, kubectl.show ${sep} ${dim}ns=${dim_green}${*} ${sep} ${dim}kind=${no_ansi}${bold}$${kind}) \
	&& ${trace_maybe} \
	&& ( kubectl get $${kind} \
			-n ${*} \
			$${kubectl_extra:-} \
		) | ${.format.header} | ${stream.as.log}

kubectl.deployments/%:; kind=deployments ${make} kubectl.show/${*}
	@# Show deployments in the given namespace
	
kubectl.svc/%:; kind=svc ${make} kubectl.show/${*}
	@# Show services in the given namespace

# kubectl.pod.get/%:; kubectl get pod ${*} -o JSON
# kubectl.pods.get:; kubectl get pod ${*} -o JSON

kubectl.stat.auth:
	$(call log.k8s, ${@} ${sep}${dim} kubectl auth whoami )
	auth_info=`\
		kubectl auth whoami -ojson 2>/dev/null \
		|| printf "${yellow}Failed to retrieve auth info with command:${no_ansi_dim} kubectl auth whoami -ojson${no_ansi}"` \
	&& printf "$${auth_info}\n"| jq .

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: kompose.* targets
##
## A small interface for working with kompose.
##
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-kompose
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

_bash.run=($(call log.io, ${bold}${cyan_flow_right} ${dim}${1}); ${1} 2> >(cut -d' ' -f2-) | ${stream.as.log})

stream.kompose.convert=${kompose.convert}/-
kompose.convert/%:; set -x && kompose -f ${*} convert -o -
	@# Runs `kompose convert` for the given file.
	@# Outputs to stdout. Also available as a macro
kompose.convert=${make} kompose.convert
kompose.convert: kompose.convert/- 
	@# Assumes stdin is a compose file, and runs `kompose.convert/`

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: istio.* targets
##
## A small interface for working with istioctl
##
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-istio
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

istio.validate/%:; $(call containerized.maybe, istioctl)
.istio.validate/%:; istioctl analyze -n ${*} 

istio.virtualservices/%:; $(call containerized.maybe, k8s)
.istio.virtualservices/%:; kind=virtualservice ${make} kubectl.show/${*}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: kubefwd.* targets
##
## The *`kubefwd.*`* targets describe a small interface for working with kubefwd.  
## It aims to cleanly background / foreground `kubefwd` in an unobtrusive way, 
## with clean setup/teardown and reasonable defaults for usage per-project.
##
## Forwarding is not just for ports but for DNS as well. 
## Note that this takes effect everywhere, including the containers inside
## k8s-tools.yml via /etc/hosts bind-mount, as it does on the docker-host.
##
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-k8smk
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

kubefwd.ctx/%:
	@# This wraps the given target, using the given given kubefwd arguments.
	@# See `flux.context_manager` docs for more details.
	@#
	@# Roughly equivalent:
	@#   kubefwd.ctx/1st,2nd => kubefwd.start/2nd 1st kubefwd.stop/2nd
	@#
	target=$(call mk.unpack_arg,1) \
	&& args=$(call mk.unpack_arg,2) \
	&& $(call log.k8s, kubefwd.ctx ${sep} $${target} ${sep} $${args}) \
	&& ${make} flux.with.ctx/$${target},kubefwd,$(call mk.unpack_arg,2)
	
kubefwd.enter/% kubefwd.start/% k8s.namespace.fwd/%:
	@# Runs kubefwd for the given namespace, finding and forwarding ports/DNS for the given 
	@# service, or for all services. This is idempotent, and implicitly stops port-forwarding 
	@# if it is running, then restarts it. 
	@#
	@# NB: This target should only run from the docker host (not from the kubefwd container),  
	@# and it assumes k8s-tools.yml is present with that filename. Simple port-mapping and 
	@# filtering by name is supported; other usage with selectors/labels/reservations/etc 
	@# should just invoke kubefwd directly.
	@#
	@# USAGE: 
	@#   ./k8s.mk kubefwd/<namespace>
	@#   ./k8s.mk kubefwd/<namespace>/<svc_name>
	@#	 kubefwd_mapping="8080:80" ./k8s.mk kubefwd/<namespace> 
	@#   kubefwd_mapping="8080:80" ./k8s.mk kubefwd/<namespace>/<svc_name>
	@#
	export pathcomp="$(shell echo ${*}| sed -e 's/\// /g')" \
	&& export namespace="$(strip $(shell echo ${*} | awk -F/ '{print $$1}'))" \
	&& export svc_name="$(strip $(shell echo ${*} | awk -F/ '{print $$2}'))" \
	&& kubefwd_mapping=$${kubefwd_mapping:-} \
	&& header="kubefwd ${sep} ${dim_green}$${namespace}" \
	&& header="$${header} ${sep} ${bold_green}$${svc_name}" \
	&& case "$${svc_name}" in \
		"") filter=$${filter:-}; ;; \
		*) \
			filter="-f metadata.name=$${svc_name}";; \
	esac \
	&& case "$${kubefwd_mapping}" in \
		"") true; ;; \
		*) kubefwd_mapping="--mapping $${kubefwd_mapping}"; ;; \
	esac \
	&& ${make} kubefwd.stop/${*} \
	&& cname=`CMK_INTERNAL=1 ${make} .kubefwd.container_name/${*}` \
	&& fwd_cmd="kubefwd svc -n $${namespace} $${filter} $${kubefwd_mapping} -v" \
	&& fwd_cmd_wrapped="docker compose -f ${K8S_TOOLS} run --name $${cname} --rm -d $${fwd_cmd}" \
	&& $(call log.k8s, $${header} ${sep} ${cyan}start) \
	&& $(call io.mktemp) \
	&& $(call _bash.run,$${fwd_cmd_wrapped}) $(_compose_quiet) \
	&& CMK_INTERNAL=1 ${make} flux.timeout/3/docker.logs/$${cname}


kubefwd.exit/% kubefwd.stop/%:
	@# Stops the named kubefwd instance.  Mostly for internal usage, 
	@# usually you want 'kubefwd.start' or 'kubefwd.panic' instead.
	@#
	@# USAGE:
	@#	./k8s.mk kubefwd.stop/<namespace>/<svc_name>
	@#
	export pathcomp="$(shell echo ${*}| sed -e 's/\// /g')" \
	&& export namespace="$(strip $(shell echo ${*} | awk -F/ '{print $$1}'))" \
	&& export svc_name="$(strip $(shell echo ${*} | awk -F/ '{print $$2}'))" \
	&& timeout=30 \
	&& header="kubefwd ${sep} ${dim_green}$${namespace}" \
	&& header="$${header} ${sep} ${bold_green}$${svc_name}" \
	&& $(call log.k8s, $${header} ${sep} ${dim_cyan}stop ${no_ansi_dim}timeout=${yellow}$${timeout}) \
	&& ${trace_maybe} \
	&& export name=`CMK_INTERNAL=1 ${make} .kubefwd.container_name/${*}` \
	&& ${make} docker.stop 2>&1 | ${stream.as.log}

kubefwd.panic:
	@# Non-graceful stop for everything that is kubefwd related.
	@# 
	@# Emergency use only; this can clutter up your /etc/hosts
	@# file as kubefwd may not get a chance to clean things up.
	@# 
	@# USAGE:  
	@#   ./k8s.mk kubefwd.panic
	@# 
	$(call log.k8s, ${@} ${sep}${no_ansi_dim}Killing all kubefwd containers)
	(${make} kubefwd.ps || echo -n) | xargs -I% bash -x -c "docker stop -t 1 %"

.kubefwd.container_name/%:
	@# Gets an appropriate container-name for the given kubefwd context.
	@# This is for internal usage (you won't need to call it directly)
	@#
	@# USAGE:
	@#	./k8s.mk .kubefwd.container_name/<namespace>/<svc_name>
	@#
	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}')))
	$(eval export svc_name:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}')))
	cname="kubefwd.`basename ${PWD}`.$${namespace}.$${svc_name:-all}" \
	&& printf "$${cname}"

kubefwd.help:; ${make} mk.namespace.filter/kubefwd.
	@# Shows targets for just the 'kubefwd' namespace.

kubefwd.stat: kubefwd.ps
	@# Display status info for all kubefwd instances that are running

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN Misc targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

ktop: ktop/all
	@# Launches ktop tool.  
	@# (This assumes 'ktop' is mentioned in 'KREW_PLUGINS')

ktop/%:; $(call containerized.maybe, k8s)
	@# Launches ktop tool for the given namespace.
	@# This works from inside a container or from the host.
	@#
	@# NB: It's the default, but this does assume 'ktop' is mentioned in 'KREW_PLUGINS'
	@#
	@# USAGE:
	@#   ./k8s.mk ktop/<namespace>
.ktop/%:
	${set_scope} \
	&& kubectl ktop $${scope}

k9s/%:; cmd="-n ${*}" ${make} k9s 
	@# Starts the k9s pod-browser TUI, opened by default to the given namespace.
	@# 
	@# NB: This assumes the `compose.import` macro has already imported k8s-tools services
	@# 
	@# USAGE:  
	@#   ./k8s.mk k9s/<namespace>

k9s.ui:; tty=0 ${make} k9s
	@# Preferred entrypoint to start the k9s UI.  This ensures ttys are setup correctly

k9: k9s.ui
	@# Starts the k9s pod-browser TUI, using whatever namespace is currently activated.
	@# This is just an alias to cover the frequent typo, and it assumes the 
	@# `compose.import` macro has already imported k8s-tools services.
	@#
	@# USAGE:  
	@#   ./k8s.mk k9

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'tilt.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-tilt
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
export TILT_PORT?=10350
TILT_URL=http://localhost:${TILT_PORT}/r/(Tiltfile)/overview

tilt.browser tilt.open: io.browser/TILT_URL
	@# Open a webbrowser for tilt webUI

tilt.get_logs/%:; $(call containerized.maybe, tilt)
	@# Not to be confused with tilt.logs, which is the tool container 
	@# USAGE: tilt.get_logs/<number_of_lines>
.tilt.get_logs/%:; TILT_PORT=$${TILT_PORT:-10350}  tilt logs | tail -${*} | ${stream.as.log}

tilt.serve/%: tilt.stop 
	@# USAGE: tilt.serve/<Tiltfile>
	export TILT_FILE=${*} \
	&& ${make} tilt.up.detach io.wait/5 tilt.logs/10 
tilt.stream:; $(call containerized.maybe, tilt)
	@# Stream logs from tilt forever
.tilt.stream:; TILT_PORT=$${TILT_PORT:-10350}  tilt logs --follow

Tiltfile.from.url:
	@# USAGE: 
	@#   url=.. Tiltfile.from.url
	${io.mktemp} \
	&& ${io.curl} $${url} > $${tmpf} \
	&& case $${quiet:-1} in \
	  0) $(call log.preview.file, $${tmpf});; \
	esac \
	&& TILT_FILE=$${tmpf} ${make} tilt.serve

# tilt.tilt_logs:; $(call containerized.maybe, tilt)
# 	@#
# .tilt.tilt_logs:; set -x && tilt logs
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN 'tui.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-tui
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# FIXME: not dry 
# export CMK_COMPOSE_FILE=.tmp.compose.mk.yml
export COMPOSE_EXTRA_ARGS=-f ${CMK_COMPOSE_FILE}

# Override compose.mk defaults 
export TUI_SVC_NAME:=tui
export TUI_COMPOSE_FILE:=k8s-tools.yml
export TUI_CONTAINER_IMAGE:=k8s:tui
export TUI_THEME_HOOK_PRE:=.tui.theme.custom
export TUI_THEME_NAME:=powerline/double/red
export TUI_SVC_BUILD_ORDER:=dind_base,tux,k8s,dind,tui

.tui.theme.custom: .tux.init.theme
	setter="tmux set -goq" \
	&& $${setter} @theme-status-interval 1 \
	&& $${setter} @themepack-status-left-area-middle-format \
		"ctx=#(kubectx -c||echo ?) ns=#(kubens -c||echo ?)" \

.tui.widget.k8s.topology.clear/%:
	clear="--clear" ${make} .tui.widget.k8s.topology/${*}

.tui.widget.k8s.topology/%: io.time.wait/2
	label="${*} topology" \
		${make} gum.style tux.require flux.loopfq/k8s.graph.tui/${*}/pod

endif
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░