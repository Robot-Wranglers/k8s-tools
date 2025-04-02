#!/usr/bin/env -S K8SMK_STANDALONE=1 make -f
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# k8s.mk: 
#   Automation library/framework/tool building on compose.mk and k8s-tools.yml
#
# DOCS: https://robot-wranglers.github.io/k8s-tools#k8smk
#
# LATEST: https://robot-wranglers.github.io/k8s-tools/tree/master/k8s.mk
#
# FEATURES:
#   1) ....................................................
#   2) Stand-alone mode also available, i.e. a tool that requires no Makefile and no compose file.
#   3) ....................................................
#   4) A small-but-powerful built-in TUI framework with no host dependencies. (See the tui.* API) 
#
# USAGE: ( For Integration )
#   # Add this to your project Makefile
#   include k8s.mk
#   include compose.mk
#   $(eval $(call compose.import, ▰, TRUE, k8s-tools.yml))
#   demo: ▰/k8s/self.demo
#   self.demo:
#       kubectl --help
#		helm --help
#
# USAGE: ( Stand-alone tool mode )
#   ./k8s.mk help
#
# APOLOGIES:
#   In advance if you're checking out the implementation.  This is unavoidably gnarly in a lot of places.
#   No one likes a file this long, and especially make-macros are not the most fun stuff to read or write.
#   Breaking this apart could make internal development easier but would complicate boilerplate required
#   for integration with external projects.  Pull requests are welcome! =P  
#
# HINTS:
#   1) The goal is that the implementation is well tested, nearly frozen, and generally safe to ignore!
#   2) If you just want API or other docs, see https://robot-wranglers.github.io/k8s-tools#compose.mk
#   3) If you need to work on this file, you want Makefile syntax-highlighting & tab/spaces visualization.
#
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

GLYPH_K8S=${green}⑆${dim}
log.k8s=$(call log, ${GLYPH_K8S} ${1})

# Hints for exactly how k8s.mk is being invoked 
export K8S_MK_SRC=$(shell echo ${MAKEFILE_LIST}|sed 's/ /\n/g' | grep k8s.mk)
ifeq ($(findstring k8s.mk, ${MAKE_CLI}),)
export K8S_MK_LIB=1
export K8S_MK_STANDALONE=0
else
export K8S_MK_LIB=0
export K8S_MK_STANDALONE=1
endif
K8S_TOOLS=`dirname ${K8S_MK_SRC}`/k8s-tools.yml

# ifeq (,$(filter compose.mk,$(MAKEFILE_LIST)))
# include compose.mk
# else
# endif

# Import compose.mk iff we're in stand-alone mode.
ifeq ($(K8S_MK_STANDALONE),1)
$(eval $(call compose.import, $(shell dirname ${K8S_MK_SRC}||echo .)/k8s-tools.yml))
loadf: self.loadf
endif

# Extra repos that are included in 'docker.images' output.  
# This is used to differentiate "local" images.
export CMK_EXTRA_REPO:=k8s

# How long to wait when checking if namespaces/pods are ready
export K8S_POLL_DELTA?=23

# Default base image.  This is used for kubectl, helm, and others.
# In some cases, KUBECTL_VERSION can override this; see the 'ansible' 
# container in k8s-tools.yml.  If used, that should match what alpine 
# is providing or it can lead to confusion.
export IMG_ALPINE_K8S?=alpine/k8s:1.30.0

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END Data & Macros
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
	@# Interface for ansible's block-in-file module[1].
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
	@# Interface for ansible's helm module[1].
	@# This accepts only module args, but there are a few ways to pass them.  
	@# See the docs in 'ansible.adhoc/<module>' for discussion of examples.
	@#
	@# * `[1]`: https://docs.ansible.com/ansible/latest/collections/kubernetes/core/helm_module.html
	@#

ansible.kubernetes.core.k8s k8s.ansible: ansible.adhoc/kubernetes.core.k8s
	@# Interface for ansible's `kubernetes.core.k8s` module[1].
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

ansible.run: 
	@# Runs the input-stream as an ansible playbook.
	@# This calls ansible in a way that ensures all output is JSON.
	@#
	@# USAGE:
	@#   cat <playbook> | ./compose.mk ansible.run
	@#
	$(call io.mktemp) \
	&& ${stream.stdin} > $${tmpf} \
	&& ${make} flux.timer/ansible.run/$${tmpf}

ansible.run/%: .ansible.require
	@# Runs the given playbook file.
	@# This calls ansible in a way that ensures all output is JSON.
	@#
	@# USAGE: 
	@#   ./k8s.mk ansible.run/<path>
	@#
	${trace_maybe} \
	&& ansible_args="-eansible_python_interpreter=\`which python3\`" \
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
## END 'ansible.*' targets
## BEGIN 'helm.*' targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-helm
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

helm.chart.install:
	@#
	@#
	@#
	@#
	$(call log.part1, $${header} ) \
	&& ${make} helm.release.stat/$${name} 2>/dev/null \
	; case $$? in \
		0) ($(call log.part2, ${dim_green}ok); ${make} helm.release.status/$${name} );; \
		*) ($(call log.part2, ${dim_ital}missing) \
			&& ${trace_maybe} && helm install $${name} $${chart_ref} -o json | jq .info);; \
	esac
helm.repo.list: helm.dispatch/.helm.repo.list
	@# Returns JSON for the currently available helm repositories.
.helm.repo.list:; helm repo list -o json

helm.repo.require/%:
	@# Add the named helm repository iff it's missing.
	@#
	@# USAGE:
	@#  url=<repo_url> ./k8s.mk helm.repo.require/<name>
	header="helm.repo.require ${sep}" \
	&& $(call log.k8s, $${header} ${dim}${bold}${*} ${sep} ${dim_ital}$${url:-no URL given})
	helm repo list -o json | jq -e -r '.[].name' 2>/dev/null \
	| grep -w ${*} || (helm repo add ${*} $${url} | ${stream.as.log})

helm.release.status/%:
	@# Interface to `helm status`, this returns information for the given release.
	@# Always returns JSON.  Not strict: no error will be 
	@# thrown in case the repo doesn't exist.
	@#
	@# USAGE:
	@#  ./k8s.mk helm.status/<release_name>
	@#
	$(call io.mktemp) \
	&& helm status ${*} -o json 2>/dev/null | jq .info > $${tmpf} \
	&& case `cat $${tmpf}` in \
		"") $(call log.k8s, helm.release.status ${sep} ${bold}${*} ${sep} ${dim_ital}no such release!);; \
		*) cat $${tmpf}| jq . ;; \
	esac

helm.release.stat/%:
	@# Like `helm.status`, but strict and quiet for use with conditionals.
	@# Result status is an error if the given repo name doesnt exist 
	@#
	@# USAGE:
	@#  ./k8s.mk helm.stat/<release_name>
	@#
	header="${GLYPH_K8S} helm.release.stat ${sep} ${bold}${*} ${sep}" \
	&& $(call log.trace,$${header} ${dim_ital} asserting release exists..) \
	&& ${make} helm.release.status/${*} 2>/dev/null| jq -e . >/dev/null

helm.release.present/%: ; ${make} helm.release.stat/${*} >/dev/null
helm.release.missing/%: ; ${make} flux.negate/helm.release.present/${*}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: helm.* targets
## BEGIN: 'k3d.* targets
##
## The *`k3d.*`* targets describe a small interface for working with `k3d`[2].  
##
## Most targets in this namespace will use k3d directly, and so are usually **dispatched**, and not run from the host.  
## Most targets are small utilities that can help to keep common tasks idempotent, but there's also a TUI that provides a useful overview of what's going on with K3d
##
## DOCS: 
##   [1]: https://robot-wranglers.github.io/k8s-tools/api#api-k3d\
##   [2]:
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Geometry for k3d.commander
GEO_K3D="5b40,111x56,0,0[111x41,0,0{55x41,0,0,1,55x41,56,0[55x16,56,0,2,55x24,56,17,3]},111x14,0,42{55x14,0,42,4,55x14,56,42,5}]"
io.curl=curl -sSL
k3d.cluster.exists/% k3d.has_cluster/%:; k3d cluster list | grep ${*}
	@# Succeeds iff cluster exists.

k3d.cluster.get_or_create/%:; $(call in.container, k3d)
	@# Create a k3d cluster if it does not already exist.
.k3d.cluster.get_or_create/%:
	$(call log.k8s, k3d.cluster.get_or_create ${sep} ${bold}${*})
	${make} flux.do.unless/k3d.cluster.create/${*},k3d.has_cluster/${*}

k3d.cluster.create/%:
	@# Creates a k3d cluster with the given name, using the given configuration.
	@# This supports most of the usual command-line options, but they are passed 
	@# as variables.
	@#
	@# USAGE:
	@#   k3d_servers=.. k3d_agents=.. 
	@#   k3d_port=.. k3d_api_port=.. 
	@#     ./k8s.mk k3d.cluster.create/<cluster_name>
	@#
	$(call log.k8s, k3d.cluster.create ${sep} ${bold}${*})
	tmp=`pwd` && set -x \
	&& k3d cluster create ${*} \
		--servers $${k3d_servers:-3} \
		--agents $${k3d_agents:-3} \
		--api-port $${k3d_api_port:-6551} \
		--volume $${tmp}/:/${*}@all --wait

# --port "$${k3d_port:-12000:12000@agent:0}" \

k3d.cluster.delete/%:; $(call in.container, k3d)
	@# Idempotent version of k3d cluster delete 
	@#
	@# USAGE:
	@#   ./k8s.mk k3d.cluster.delete/<cluster_name>
.k3d.cluster.delete/%:
	$(call log.k8s, ${@} ${sep} Deleting cluster ${sep}${underline}${*})
	(set -x && k3d cluster delete ${*}) || true

k3d.cluster.list k3d.list:; $(call in.container, k3d)
	@# Returns cluster-names, newline delimited.
	@#
	@# USAGE:  
	@#   ./k8s.mk k3d.cluster.list
	@# 
.k3d.cluster.list .k3d.list:
	k3d cluster list -o json | ${jq} -r '.[].name' \
	| xargs -n1 echo  | ${stream.indent}

k3d.commander:
	@# Starts a 4-pane TUI dashboard, using the commander layout.  
	@# This opens 'lazydocker', 'ktop', and other widgets that are convenient for working with k3d.
	@#
	@# USAGE:  
	@#   KUBECONFIG=.. ./k8s.mk k3d.commander/<namespace>
	@# 
	$(call log.k8s, k3d.commander ${sep} ${no_ansi_dim}Opening commander TUI for k3d)
	geometry="${GEO_K3D}" ${make} tux.open/flux.loopf/k9s,flux.loopf/k3d.stat
# TUI_CMDR_PANE_COUNT=5 TUI_LAYOUT_CALLBACK=.k3d.commander.layout ${make} tux.commander
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

k3d.panic:
	@# Non-graceful stop for everything that is k3d related. 
	@# 
	@# USAGE:  
	@#   ./k8s.mk k3d.panic
	@# 
	$(call log.k8s, ${@} ${sep} Stopping all k3d containers)
	(${make} k3d.ps || echo -n) | xargs -I% bash -x -c "docker stop -t 1 %"

# k3d.ps:
# 	@# Container names for everything that is k3d related.
# 	@#
# 	@# USAGE:  
# 	@#   ./k8s.mk k3d.ps
# 	@# 
# 	$(call log, ${dim}${GLYPH_K8S} ${@} ${sep}${dim} Listing k3d containers)
# 	(docker ps --format json \
# 	| ${jq} -r '.Names' \
# 	| grep ^k3d- \
# 	|| printf "${yellow}No containers found.${no_ansi}\n" > ${stderr} ) ${stderr_stdout_indent}

k3d.stat: 
	@# Show status for k3d.
	@# 
	$(call log.k8s, k3d.stat)
	$(trace_maybe) && ${make} k3d.ps k3d.cluster.list 

# k3d.stat.widget:
# 	clear=1 verbose=1 interval=10 ${make} flux.loopf/flux.apply/k3d.stat


#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END 'k3d.*' targets
## BEGIN 'k8s.*' targets
##
## This is the default target-namespace for `k8s.mk`.  It covers general helpers.  
##
##
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-k8s
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


kubectl.get/%:
	@# Returns resources under the given namespace, for the given kind.
	@# This can also be used with a 'jq' query to grab deeply nested results.
	@# Pipe Friendly: results are always JSON.  Caller should handle errors.
	@#
	@# USAGE: 
	@#	 ./k8s.mk kubectl.get/<namespace>/<kind>/<resource_name>/<jq_filter>
	@#
	@# Argument for 'kind' must be provided, but may be "all".  
	@# Argument for 'filter' is optional.
	@#
	$(eval export pathcomp:=$(shell echo ${*}| sed -e 's/\// /g'))
	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}')))
	$(eval export kind:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}')))
	$(eval export name:=$(strip $(shell echo ${*} | awk -F/ '{print $$3}')))
	$(eval export filter:=$(strip $(shell echo ${*} | awk -F/ '{print $$4}')))
	export cmd_t="kubectl get $${kind} $${name} -n $${namespace} -o json | jq -r $${filter}" \
	&& $(call log.k8s, kubectl.get${no_ansi_dim} // $${cmd_t}) \
	&& eval $${cmd_t}

kubectl.apply.stdin:
	@#
	@#
	@#
	@#
	$(call log.k8s, ${@} ${sep} ${cyan_flow_left})
	${stream.stdin} | yq . -o json | ${stream.peek} | kubectl apply -f - 
kubectl.apply.url:; ${io.get.url} && ${make} kubectl.apply/$${tmpf}

kubectl.apply/%:
	@# Runs kubectl apply on the given file
	@# Also available as a macro.
	kubectl apply -f ${*} 2> >(grep -v "missing the kubectl.kubernetes.io/last-applied-configuration annotation")

kubectl.apply=${make} kubectl.apply

kubectl.namespace.list:
	@# Returns all namespaces in a simple array.
	@# NB: Must remain suitable for use with `xargs`!
	@#
	kubectl get namespaces -o json \
	| jq -r '.items[].metadata.name'

kubectl.namespace.purge/%:
	@# Wipes everything inside the given namespace
	@#
	@# USAGE: 
	@#    kubectl.namespace.purge/<namespace>
	@#
	$(call log.k8s, kubectl.namespace.purge ${sep} ${no_ansi}${green}${*} ${sep} Waiting for delete (cascade=foreground))
	${trace_maybe} \
	&& kubectl delete namespace --cascade=foreground ${*} -v=9 2>/dev/null || true

kubectl.namespace.purge.by.prefix/%:
	@# Runs a separate purge for every matching namespace.
	@# NB: This isn't likely to clean everything, see the docs for your dependencies.
	@#
	@# USAGE: 
	@#    ./k8s.mk kubectl.namespace.purge.by.prefix/<prefix>
	@#
	${make} kubectl.namespace.list \
	| grep ${*} | ${stream.peek} \
	| xargs -I% bash -x -c "${make} kubectl.namespace.purge/%"
	|| $(call log.k8s, ${@} ${sep} ${dim}Nothing to purge: no namespaces matching \`${*}*\`)

kubectl.namespace.create/%:
	@# Idempotent version of namespace-create.
	@#
	@# USAGE: 
	@#    kubectl.namespace.create/<namespace>
	@#
	$(call log.k8s, kubectl.namespace.create ${sep} ${bold}${*} ${sep} )
	kubectl create namespace ${*} \
		--dry-run=client -o yaml \
	| ${stream.peek} | kubectl apply -f - \
	2>&1

kubectl.cluster.ready/%:
	@#
	@#
	@#
	KUBECONFIG=${*} kubectl cluster-info > /dev/null 2>&1 \
	; case $$? in \
		0) $(call log.k8s, k8s.cluster.ready ${sep} Cluster connectivity ok); exit 0; ;; \
		*) $(call log.k8s, k8s.cluster.ready ${sep} Failed to connect to the cluster); exit 1; ;; \
	esac

kubectl.exec.pipe/%:
	@#
	@# USAGE: Stream commands into a pod:
	@#   echo uname -a | ./k8s.mk k8s.shell/<namespace>/<pod_name>/pipe
	@#
	namespace=$(shell echo ${*}|awk -F/ '{print $$1}') \
	&& pod_name=$(shell echo ${*}|awk -F/ '{print $$2}') \
	&& ${stream.stdin} | docker compose -f ${K8S_TOOLS} run -T k8s \
		sh -x -c "KUBECONFIG=${KUBECONFIG} kubectl exec -n $${namespace} -i $${pod_name} -- bash"

kubectl.shell/%:
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
	@# USAGE: Interactive shell in pod:
	@#   ./k8s.mk k8s.shell/<namespace>/<pod_name>
	namespace=$(shell echo ${*}|awk -F/ '{print $$1}') \
	&& pod_name=$(shell echo ${*}|awk -F/ '{print $$2}') \
	&& docker compose -f `dirname ${K8S_MK_SRC}`/k8s-tools.yml run k8s \
		sh -x -c "KUBECONFIG=${KUBECONFIG} kubectl exec -n $${namespace} -it $${pod_name} -- bash"

kubectl.get.nodes:
	@# Status for nodes. 
	@# Not machine-friendly.  See instead 'kubectl.get'.
	@#
	node_count=`kubectl get nodes -oname|wc -l` \
	&& $(call log.k8s, ${@} (${no_ansi}${green}$${node_count}${no_ansi_dim} total))
	kubectl get nodes

kubectl.stat.cluster:
	@# Shows cluster status.
	@#
	$(call log.k8s, ${@} ${sep}${no_ansi_dim} Showing cluster status..)
	kubectl version -o json 2>/dev/null | jq . || true
	kubectl cluster-info -o json 2>/dev/null  | jq . || true

kubectl.stat.auth:
	$(call log.k8s, ${@} ${sep}${dim} kubectl auth whoami )
	auth_info=`\
		kubectl auth whoami -ojson 2>/dev/null \
		|| printf "${yellow}Failed to retrieve auth info with command:${no_ansi_dim} kubectl auth whoami -ojson${no_ansi}"` \
	&& printf "$${auth_info}\n"| jq .

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

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

# define Dockerfile.convert
# FROM alpine
# #RUN apk add -q --update --no-cache coreutils build-base bash procps-ng graphviz imagemagick
# RUN apk add -q --update --no-cache bash imagemagick
# endef
# define Dockerfile.dot
# FROM alpine
# #RUN apk add -q --update --no-cache coreutils build-base bash procps-ng graphviz imagemagick
# RUN apk add -q --update --no-cache bash graphviz
# ENTRYPOINT dot
# endef
# $(eval $(call compose.import.dockerfile.string,Dockerfile.dot))

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
	@# Previews topology for a given kubernetes <namespace>/<kind> in a way that's terminal-friendly.
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

argo.list: argo.list/argo 
	@# List for the default namespace (i.e. "argo")

argo.list/%:; argo -n ${*} list 
	@# Returns the results of 'argo list' for the current argo context.

argo.submit.url:
	$(call log.k8s, ${@} ${sep} ${cyan_flow_left})
	${io.get.url} && cat $${tmpf} | ${make} argo.submit.stdin

argo.submit.stdin=${make} argo.submit.stdin 
argo.submit.stdin stream.argo.submit :
	@# Submits a workflow from stdin using the argo CLI.
	@#
	@# USAGE:
	@#   cat <fname> | ./k8s.mk argo.submit.stdin
	@#
	$(call log.k8s, ${@} ${sep} ${cyan_flow_left})
	${stream.peek} | ${make} argo.submit/-

argo.submit/%:
	@# Submits the given file as a workflow, using the argo CLI.
	@# 
	@# USAGE:
	@#   ./k8s.mk argo.submit/<fname>
	@# 
	$(call log.k8s, ${@} ${sep} ${cyan_flow_left})
	log="--log" \
	&& wait=`[ -z $${wait:-} ] && true || echo "--wait"` \
	&& case ${*} in \
		-) path=/dev/stdin;; \
		*) path=${*};; \
	esac \
	&& set -x && argo submit $${log} $${wait} $${path}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

k8s.help:; ${make} mk.namespace.filter/k8s.
	@# Shows targets for just the 'k8s' namespace.

k8s.kubens/%: 
	@# Context-manager.  Activates the given namespace.
	@# NB: This modifies state in the kubeconfig, so that it can effect contexts 
	@# outside of the current process, therefore this is not thread-safe.
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

k8s.namespace.wait/%:
	@# Waits for every pod in the given namespace to be ready.
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
	export scope=`[ "${*}" == "all" ] && echo "--all-namespaces" || echo "-n ${*}"` \
	&& export header="k8s.namespace.wait ${sep} ${green}${*}${no_ansi}" \
	&& wait_cmd="gum \
		spin --spinner $${spinner:-jump} \
		--spinner.foreground=$${color:-39} \
		--title=\"Waiting ${K8S_POLL_DELTA}s\" \
		-- sleep ${K8S_POLL_DELTA}" \
	&& $(call log.k8s, $${header} ${sep}${dim} Looking for pending pods) \
	&& until \
		kubectl get pods $${scope} -o json 2> /dev/null \
		| jq '[.items[].status.containerStatuses[]|select(.state.waiting)]' 2> /dev/null \
		| jq '.[] | halt_error(length)' 2> /dev/null \
	; do \
		case $${verbose:-1} in \
			1) ${make} kubectl.sick.pods/${*};; \
			*) true;; \
		esac \
		&& $(call log.k8s, $${header} ${sep}${dim} ${yellow}${io.timestamp} ${sep} ${bold}Pods aren't ready yet) \
		&& eval $${wait_cmd}; \
	done \
	&& tmp=`[ "${*}" == "all" ] && echo Cluster || echo Namespace` \
	&& $(call log.k8s, $${header} ${sep}${dim} $${stamp} ${sep} $${tmp} ready ${GLYPH_SPARKLE})
kubectl.sick.pods/%:
	export scope=`[ "${*}" == "all" ] && echo "--all-namespaces" || echo "-n ${*}"` \
	&& kubectl sick-pods $${scope} 2>&1 \
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
k8s.ready k8s.cluster.ready:; $(call in.container, k8s)
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
	@#
	quiet=1 ${make} k8s.dispatch/kubectl.cluster.ready/$${KUBECONFIG}

k8s.stat:; $(call in.container, k8s)
	@# Describes status for cluster, cluster auth, and namespaces.
	@# Not pipe friendly, and not suitable for parsing!  
	@#
	@# This is just for user information, as it's generated from 
	@# a bunch of tools that are using very different output styles.
	@#
	@# For a shorter, looping version that's suitable as a tmux widget, see 'k8s.stat.widget'
	@#
	case $${CMK_INTERNAL} in \
		0)  ${log.target.rerouting} \
			; quiet=1 ${make} k8s.dispatch/${@} \
			; exit $$? ; ;; \
		*) true \
			&& tmp1=`kubectx -c||true` && tmp2=`kubens -c ||true` \
			&& $(call log.k8s, k8s.stat ${no_ansi_dim}ctx=${green}${underline}$${tmp1}${no_ansi_dim} ns=${green}${underline}$${tmp2}) \
			&& ${make} k8s.stat.env kubectl.stat.cluster \
				kubectl.get.nodes kubectl.stat.auth  \
				k8s.stat.ns k8s.stat.ctx; ;; \
	esac
k8s.test_harness.random:; ${make} k8s.test_harness/default/`uuidgen`
	@# Starts a test-pod with a random name in the given namespace, optionally blocking until it's ready.
	@#
	@# USAGE: 
	@#	`k8s.test_harness.random`

k8s.test_harness/%:; $(call in.container, k8s)
	@# Starts a test-pod in the given namespace, optionally blocking until it's ready.
	@# When no image is provided, this will use 'IMG_ALPINE_K8S' as default.
	@#
	@# USAGE: 
	@#	`k8s.test_harness/<namespace>/<pod_name>` or 
	@#	`k8s.test_harness/<namespace>/<pod_name>/<image>` 
	@#
.k8s.test_harness/%:
	$(eval export pathcomp:=$(shell echo ${*}| sed -e 's/\// /g'))
	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}'))) \
	$(eval export pod_name:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}'))) \
	$(eval export rest:=$(strip \
		$(shell echo $(wordlist 3,99,$${pathcomp}) | sed -e 's/ /\//g')))
	$(trace_maybe) \
	&& export pod_name=$${pod_name:-test-harness} \
	&& export pod_image=$${rest:-$${IMG_ALPINE_K8S}} \
	&& $(call log.k8s, k8s.test_harness ${sep} ${green}$${namespace}) \
	&& export data="{ \
		\"apiVersion\": \"v1\", \"kind\":\"Pod\", \
		\"metadata\":{\"name\": \"$${pod_name}\"}, \
		\"spec\":{ \
			\"containers\": [ {\
				\"name\": \"$${pod_name}-container\", \
				\"tty\": true, \"stdin\": true,\
				\"image\": \"$${pod_image}\", \
				\"command\": [\"sleep\", \"infinity\"] } ] } \
		}"\
	&& export manifest=`printf "$${data}" |jq .` \
	&& printf "${dim}$${manifest}\n${no_ansi}" > ${stderr} \
	&& printf "$${manifest}" \
		| jq . \
		| (set -x && kubectl apply --namespace $${namespace} -f -) \
	&& [ -z $${wait:-} ] && true || ${make} k8s.namespace.wait/$${namespace}


k8s.wait k8s.cluster.wait: k8s.namespace.wait/all
	@# Waits until all pods in all namespaces are ready.  (Alias for 'k8s.namespace.wait/all')

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END 'k8s.*' targets
## BEGIN '.k8s.*' private targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-k8s
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

k8s.stat.env:
	@# Shows cluster, kube, and docker environment variables
	@#
	$(call log.k8s, ${@} ) 
	(   (env | grep CLUSTER || true) \
	  ; (env | grep KUBE    || true) \
	  ; (env | grep DOCKER  || true) \
	) | ${stream.indent} 

k8s.stat.ns:
	@# Shows all namespaces for the current cluster.
	@# (This is just the output of `kubens` with no arguments)
	$(call log.k8s, ${@} ${sep} ${dim}Listing namespaces)
	kubens | ${stream.indent} 

k8s.stat.ctx:
	@# Output of `kubectx`
	@#
	$(call log.k8s, ${@} ${sep} ${no_ansi_dim}Showing cluster context)
	kubectx | ${stream.indent} 

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: k8s.* targets
## BEGIN: kubefwd.* targets
##
## The *`kubefwd.*`* targets describe a small interface for working with kubefwd.  
## It aims to cleanly background / foreground `kubefwd` in an unobtrusive way, 
## with clean setup/teardown and reasonable defaults for usage per-project.
##
##
## Forwarding is not just for ports but for DNS as well. 
## Note that this takes effect everywhere, including the containers inside
## k8s-tools.yml via /etc/hosts bind-mount, as it does on the docker-host.
##
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-k8smk
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

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
	cname=kubefwd.`basename ${PWD}`.$${namespace}.$${svc_name:-all} \
	&& printf $${cname}

kubefwd.help:; ${make} mk.namespace.filter/kubefwd.
	@# Shows targets for just the 'kubefwd' namespace.

kubefwd.stop/%:
	@# Stops the named kubefwd instance.
	@# This is mostly for internal usage, usually you want 'kubefwd.start' or 'kubefwd.panic'
	@#
	@# USAGE:
	@#	./k8s.mk kubefwd.stop/<namespace>/<svc_name>
	@#
	timeout=30 \
	name=`${make} .kubefwd.container_name/${*}` \
	${make} docker.stop || true

kubefwd.stat: kubefwd.ps
	@# Display status info for all kubefwd instances that are running

kubefwd.start/% k8s.namespace.fwd/%:
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
	@#	 mapping="8080:80" ./k8s.mk kubefwd/<namespace> 
	@#   mapping="8080:80" ./k8s.mk kubefwd/<namespace>/<svc_name>
	@#
	$(eval export pathcomp:=$(shell echo ${*}| sed -e 's/\// /g'))
	$(eval export namespace:=$(strip $(shell echo ${*} | awk -F/ '{print $$1}')))
	$(eval export svc_name:=$(strip $(shell echo ${*} | awk -F/ '{print $$2}')))
	mapping=$${mapping:-} \
	&& header="kubefwd ${sep} ${dim_green}$${namespace}" \
	&& case "$${svc_name}" in \
		"") filter=$${filter:-}; ;; \
		*) \
			filter="-f metadata.name=$${svc_name}"; \
			header="$${header} ${sep} ${bold_green}$${svc_name}"; ;; \
	esac \
	&& case "$${mapping}" in \
		"") true; ;; \
		*) mapping="--mapping $${mapping}"; ;; \
	esac \
	&& ${make} kubefwd.stop/${*} \
	&& cname=`${make} .kubefwd.container_name/${*}` \
	&& fwd_cmd="kubefwd svc -n $${namespace} $${filter} $${mapping} -v" \
	&& fwd_cmd_wrapped="docker compose -f k8s-tools.yml run --name $${cname} --rm -d $${fwd_cmd}" \
	&& $(call log.k8s, $${header}) \
	&& echo {} \
		| ${make} stream.json.object.append key=namespace val="$${namespace}" \
		| ${make} stream.json.object.append key=svc val="$${svc_name}" \
		| ${stream.as.log} \
	&& $(call log.k8s, kubefwd ${sep} ${dim}container=${no_ansi}$${cname}) \
	&& $(call log.k8s, kubefwd ${sep} ${dim}cmd=${no_ansi}$${fwd_cmd}) \
	&& $(call io.mktemp) \
	&& bash -x -c "$${fwd_cmd_wrapped} > $${tmpf}" \
	&& cid="`cat $${tmpf}|${stream.trim}`" \
	&& cmd="docker logs -f $${cname}" timeout=3 ${make} flux.timeout.sh 
	
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END 'kubefwd.*' targets
## BEGIN Misc targets
## DOCS: 
##   [1] https://robot-wranglers.github.io/k8s-tools/api#api-k8smk
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

ktop: ktop/all
	@# Launches ktop tool.  
	@# (This assumes 'ktop' is mentioned in 'KREW_PLUGINS')

ktop/%:; $(call in.container, k8s)
	@# Launches ktop tool for the given namespace.
	@# This works from inside a container or from the host.
	@#
	@# NB: It's the default, but this does assume 'ktop' is mentioned in 'KREW_PLUGINS'
	@#
	@# USAGE:
	@#   ./k8s.mk ktop/<namespace>
.ktop/%:
	scope=`[ "${*}" == "all" ] && echo "--all-namespaces" || echo "-n ${*}"` \
	&& kubectl ktop $${scope}


k9s/%:; cmd="-n ${*}" ${make} k9s 
	@# Starts the k9s pod-browser TUI, opened by default to the given namespace.
	@# 
	@# NB: This assumes the `compose.import` macro has already imported k8s-tools services
	@# 
	@# USAGE:  
	@#   ./k8s.mk k9s/<namespace>

k9: k9s
	@# Starts the k9s pod-browser TUI, using whatever namespace is currently activated.
	@# This is just an alias to cover the frequent typo, and it assumes the 
	@# `compose.import` macro has already imported k8s-tools services.
	@#
	@# USAGE:  
	@#   ./k8s.mk k9

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END misc targets
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

k8s.commander:
	@# TUI layout providing an overview for docker.  
	@# This has 3 panes by default, where the main pane is lazydocker, plus two utility panes.
	@# Automation also ensures that lazydocker always starts with the "statistics" tab open.
	@#
	$(call log.k8s, ${@} ${sep}${dim} Opening commander TUI for k8s)
	TUI_LAYOUT_CALLBACK=.tui.k8s.commander.layout \
		TUI_CMDR_PANE_COUNT=4 ${make} tux.commander

k8s.commander/%:
	@# Sends the given target(s) to the main pane.
	@#
	@# USAGE:
	@#   ./k8s.mk k8s.commander/<target1>,<target2>
	@#
	export k8s_commander_targets="${*}" && ${make} k8s.commander

.tui.k8s.commander.layout: 
	$(call log.k8s, ${@} ${sep} ${no_ansi_dim}Starting widgets and setting geometry..)
	${make} .tux.pane/3/.tui.widget.k8s.topology.clear/kube-system
	${make} .tux.pane/2/.tui.widget.k8s.topology.clear/default
	${make} .tux.pane/1/flux.loopf/.tux.widget.env/K
	${make} .tux.pane/0/flux.wrap/docker.stat,k8s.stat,$${k8s_commander_targets:-}
	${make} .tux.commander.layout
	title="main" ${make} .tux.pane.title/1
	title="default namespace" ${make} .tux.pane.title/3
	title="kube-system namespace" ${make} .tux.pane.title/4

.tui.widget.k8s.topology.clear/%:
	clear="--clear" ${make} .tui.widget.k8s.topology/${*}

.tui.widget.k8s.topology/%: io.time.wait/2
	label="${*} topology" \
		${make} gum.style tux.require flux.loopfq/k8s.graph.tui/${*}/pod

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

promtool.pull: 
	$(call gum.style.target)
	$(call log.k8s, pulling data with promtool)
	query="fission_function_calls_total{function_name=\"${FISSION_APP_NAME}\", namespace=\"fission\"}" \
	&& before=`date --date='-120 minutes' '+%s'` \
	&& after=`date --date='+120 minutes' '+%s'` \
	&& set -x && promtool \
		query series \
		--match "$${query}" \
		--start $${before} --end $${after} \
		${PROM_URL} \
	&& set +x \
	&& $(call log.k8s, pulling data with curl and visualizing it) \
	&& $(call io.mktemp) \
	&& curl -s "${PROM_URL}/api/v1/query_range" \
		--data-urlencode "query=$${query}" \
		--data-urlencode "start=$${before}" \
		--data-urlencode "end=$${after}" \
		--data-urlencode 'step=60s' \
	| jq -r .data.result[0].values[][1] > $${tmpf} \
	&& cat $${tmpf} | spark

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
