## Automation With k8s.mk
<hr style="width:100%;border-bottom:3px solid black;">

As an automation library or stand-alone tool, `k8s.mk` can help to create project-specific APIs that use the tool containers described in `k8s-tools.yml`.  Most of what's offered is in the form of **targets**, which you can directly use from the command line, or use as part of normal tasks/prereqs inside your project Makefile.  In other words, **the API and the CLI are the same**.  

Many targets are [scaffolded](#tool-container-basics), i.e. automatically generated for each tool container that's available.  Others targets are static, basically composing more primitive functionality to make it suitable for orchestration tasks.  Static targets usually fall into one of a few basic categories:

1. **Reusable implementations for common cluster automation tasks,** like [waiting for pods to get ready](/k8s-tools/api#k8s.wait)
1. **Context-management tasks,** (like [setting the currently active namespace](/k8s-tools/api#k8snamespacearg))
1. **Interactive debugging tasks,** (like [shelling into a new or existing pod inside some namespace](/k8s-tools/api#k8sshellarg))

--------------------------------

This section is a quick overview of some of the capabilities, using a combination of working CLI-style examples, and *snippets* of scripts to illustrate ideas.

If you're looking instead for an API reference, [that is here](/k8s-tools/api/#api-k8smk)).

If you want to focus on scripting and prefer to see **concrete end-to-end examples**, start instead with the demos, such as the [Cluster Lifecycle Demo](/k8s-tools/demos#demo-cluster-automation).

### Tool Container Basics
<hr style="width:100%;border-bottom:3px solid black;">

Let's start with the basic stuff.  Commands in this section are all examples of *generic target scaffolding* that is generated automatically for all tool containers, including any containers that are user-defined later.  This functionality is inherited from [`compose.mk`](https://robot-wranglers.github.io/compose.mk).  Full documentation for scaffolding is out of scope here since it really isn't kubernetes specific, but it's worth covering briefly.  See the upstream docs for [more details](https://robot-wranglers.github.io/compose.mk/bridge/#target-scaffolding).

Other external documentation might also be of interest.  Combining `k8s.mk` helpers with the `compose.mk` [workflow support](https://robot-wranglers.github.io/compose.mk/standard-lib/#workflow-support) is often useful, since you can easily accomplish things like retries, delayed actions, conditional actions and lots of other stuff.  By using the [`tux.*` API](https://robot-wranglers.github.io/compose.mk/embedded-tui/) you can send tasks, or groups of tasks, into panes on a TUI.

#### Listing Available Tools 
<hr style="width:95%;border-bottom:1px dashed black;">

First, how about getting a list of tool containers that are defined?

```bash 
$ ./k8s.mk k8s-tools.services
ansible
argo
awscli
aws-iam-authenticator
cdk
dind
eksctl
fission
graph-easy
helm
helm-diff
helmify
helm-push
helm-unittest
istioctl
k3d
k8s
k9s
kind
kn
kompose
krew
kubeconform
kubectl
kubectl_exec
kubefwd
kubeseal
kustomize
lazydocker
promtool
rancher
subctl
tui
vals
```

#### Shells & Task Dispatch
<hr style="width:95%;border-bottom:1px dashed black;">

Ok, what about shelling into a tool container to use commands directly?  We can do that and more, thanks to lots of generic targets that are generated for each container.

```bash
# Interactive shell into the kubectl container
$ ./k8s.mk kubectl.shell

# Send commands to the rancher container
$ echo rancher --version | ./k8s.mk rancher.shell.pipe
rancher version v2.8.4

# Dispatch any existing `make` target inside the given container
$ label="hello world" ./k8s.mk k3d.dispatch/io.print.banner
```

Dispatching tasks inside containers is a core feature of `compose.mk`, basically allowing for something like "agents" in jenkins, or "jobs" in Github Actions without locking your automation up inside proprietary platforms or file formats.  The k8s-tools suite organizes around this idea, describing tasks in `k8s.mk`, containers in `k8s-tools.yml`, and leveraging dispatch to accomplish "runs anywhere" style orchestration that you can then extend and compose inside your own scripts.

#### Container Meta
<hr style="width:95%;border-bottom:1px dashed black;">

Besides command execution and dispatch, there are various commands that operate on the containers themselves.  These roughly follow the `docker compose ..` verbs.  See the main docs [here](https://robot-wranglers.github.io/compose.mk/bridge/#top-level-container-handles)

```bash 
# Force a rebuild of the helm container, even if it's cached.
$ force=1 ./k8s.mk helm.build

# Show running kubefwd instances 
$ ./k8s.mk kubefwd.ps 
```
<br/>

### Cluster CRUD
<hr style="width:100%;border-bottom:3px solid black;">

For creating, updating, and deleting clusters, the  [k3d API](/k8s-tools/api/#api-k3d) and the [kind API](/k8s-tools/api/#api-k3d) are the main resources you're probably interested in.  

Using `k3d` is usually good enough and requires no external configuration for node-groups, so that is usually the best choice.  Jump to the [Cluster Lifecycle Demo](/k8s-tools/demos#demo-cluster-automation) for a more substantial demo with scripting, but read on for the basics.

```bash 
# Prep a blank kubeconfig 
$ touch mycluster.conf; chmod 711 mycluster.conf; export KUBECONFIG=./mycluster.conf 

# Bootstrap a named cluster
$ ./k8s.mk k3d.cluster.get_or_create/mycluster

⇄ k3d.cluster.get_or_create/.. // Invoked from top; rerouting to tool-container 
⑆ k3d.cluster.get_or_create // mycluster 
Φ flux.if.then // flux.negate/k3d.has_cluster/mycluster .. true 
Φ flux.if.then // k3d.cluster.create/mycluster
⑆ k3d.cluster.create // mycluster 
+ k3d cluster create mycluster --servers 3 --agents 3 --api-port 6551 --volume /workspace/:/mycluster@all --wait
...

# Check it out
$ ./k8s.mk k3d.cluster.list k3d.stat

# Wipe it out.  (Skip this if you're using it in the next demos)
$ ./k8s.mk k3d.cluster.delete/mycluster
```

Interesting, right? A stand alone, project local cluster where even the nodes are dockerized, and without even installing `k3d` as a dependency. See the [Lifecycle Demo](/k8s-tools/demos/cluster-lifecycle) for a more complete example with scripting, or the [Multicluster Demo](/k8s-tools/demos/multicluster) for an example with 2 clusters.

### Basic Platforming
<hr style="width:100%;border-bottom:3px solid black;">

For this section, `KUBECONFIG` should already be set, and you might want to use the cluster from the last section.

#### Helm
<hr style="width:95%;border-bottom:1px dashed black;">

With the k8s-tools suite, you can use `helm` directly but the simplest and most idempotent approach to installing things is usually via 
[`ansible.helm`](/k8s-tools/api/#ansiblehelm).  *(See also the [upstream ansible docs](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/helm_module.html))*



We'll also need JSON input for this part, which `k8s.mk` inherits via [compose.mk](https://robot-wranglers.github.io/compose.mkstandard-lib/#structured-io), by way of the json.bash tool[^1].  As usual, no host dependencies are for this tool, or helm, or ansible, and everything is done via docker.  

The actual output is colored and easier to parse, but usage looks like this:

```bash
# Test out the jb tool.
$ ./k8s.mk jb name=ahoy \
    release_namespace=default \
    chart_ref=hello-world \
    chart_repo_url="https://helm.github.io/examples"

{ .. }

# Pipe JSON to helm
$ ./k8s.mk jb name=ahoy \
    release_namespace=default \
    chart_ref=hello-world \
    chart_repo_url="https://helm.github.io/examples" \
  | ./k8s.mk ansible.helm
  
⑆ ansible // kubernetes.core.helm // ← 
{
"name": "ahoy",
"release_namespace": "default",
"chart_ref": "hello-world",
"chart_repo_url": "https://helm.github.io/examples"
}
⑆ ansible // kubernetes.core.helm // →
{
  "changed": true,
  "action": "kubernetes.core.helm",
  "stats": {
    "changed": 1,
    "ok": 1
  }
}
```

Tidy. We took advantage of a discrete and useful piece of ansible without installing python, or ansible, or getting sucked into a never-ending process of ansibling all the things.

#### Blocking And Paralellism
<hr style="width:95%;border-bottom:1px dashed black;">

Since kubernetes is a distributed system, we don't necessarily want to be restricted to sequential activities in our scripts.  There are several ways to go about this, and lots of utilities in the k8s-tools suite will individually default to async and optionally support some kind of `--wait` argument. 

Actually the helm commands in the last section can be turned into blocking ones by simply passing `wait=true`, but suppose you don't know this though, or the tool doesn't support it, or orchestration is much more complex.  In this case and in many others, 
[`k8s.wait`](/k8s-tools/api/#k8swait) is your best friend.

Changing the previous helm example to wait for the whole cluster to settle looks like this:

```bash
$ ./k8s.mk jb name=ahoy \
    release_namespace=default \
    chart_ref=hello-world \
    chart_repo_url="https://helm.github.io/examples" \
  | ./k8s.mk ansible.helm \
  && ./k8s.mk k8s.wait
```

This shows a looping status display which shows exactly what's still pending and what the cluster is up to.  Under the hood, it uses a colorized, looping version of krew's kubectl-sick-pods plugin[^2].

In a similar fashion you can use 
[`k8s.namespace.wait/<namespace>`](/k8s-tools/api/#k8snamespacewaitarg) to block on one particular namespace, which opens up more interesting possibilities.  

As highlighted elsewhere, the nature of Makefile ensures that the `k8s.mk` CLI is essentially one-to-one with the API.  So thanks to that, **tools like `k8s.wait` aren't just commands, but also a powerful synchronization primitive in scripting**, especially when they are used as target prerequisites.  Consider the following snippet of Makefile:

```Makefile
# Create and enter the `my_platform` namespace before we do anything
setup.platform:
	kubectl apply ...

# Blocks on `my_platform` being paved, then sets namespace as default and continues
setup.app: k8s.namespace.wait/my_platform 
	kubectl apply ...

bootstrap: setup.platform setup.logging setup.monitoring setup.app
```

Of course you could do this in pure shell or a variety of other ways.  Preferring a Makefile tends to keep things really organized though, and we retain the ability to execute every piece of it individually, rather than being stuck with some kind of top-to-bottom execution of everything.  Much more advanced stuff is possible by combining make's [native support for parallelism](https://www.gnu.org/software/make/manual/html_node/Parallel.html) and its own [synchronization primitives](https://www.gnu.org/software/make/manual/html_node/Parallel-Disable.html).


<hr style="width:100%;border-bottom:3px solid black;">

[^1]: [https://github.com/h4l/json.bash](https://github.com/h4l/json.bash)
[^2]: [https://github.com/alecjacobs5401/kubectl-sick-pods](https://github.com/alecjacobs5401/kubectl-sick-pods)



