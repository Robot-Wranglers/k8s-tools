## Automation With k8s.mk
<hr style="width:100%;border-bottom:3px solid black;">

!!! note "Note"
    As an automation library or stand-alone tool, `k8s.mk` can help to create project-specific APIs that use the tool containers described in `k8s-tools.yml`.   This page is a gentle introduction to how that automation works, and how it's organized.
    
    See [the scripting demos](/k8s-tools/demos/) instead to dive into examples, or the [tool-mode docs](/k8s-tools/tool-mode) for information about stand-alone mode.  See also [the upstream compose.mk docs](https://robot-wranglers.github.io/compose.mk). 

Most of what's offered is in the form of **make targets**, which you can directly use from the command line, or use as part of normal tasks/prereqs inside a project Makefile.


### Internal vs External API 
<hr style="width:100%;border-bottom:3px solid black;">

With Makefile, **the internal automation API and the CLI are effectively the same thing,** which is important to understand when looking over the documentation.  Let's look at a quick example of that before we get into the rest of the background.  

------------------------

Suppose you want to wait for your cluster to settle before you do something else.  If you're building or debugging interactively or scripting with bash, you might just want a shell command:

```bash {.cli_example}
# Blocks until there are no pods with status=waiting and pending jobs are completed
$ KUBECONFIG=.. ./k8s.mk k8s.wait
```

------------------------

If instead you are scripting as part of a bigger orchestration project, you might put this in your project Makefile:

```Makefile {.language-makefile .snippet}
# your project Makefile 
include k8s.mk 

deploy.app: k8s.wait
	kubectl ..
```

------------------------

In summary, almost everything is a target[^1], but `k8s.mk` has two kinds of targets available in the public interface.

### Overview
<hr style="width:100%;border-bottom:3px solid black;">

!!! road_map "Road Map"
    **Scaffolded Targets**:
    :  That is, [automatically generated](#tool-container-basics) targets for each tool container that's available. Scaffolded targets are focused on the standard docker compose container verbs, such as *run / exec / up / down*, plus what you might call *mapping and dispatch*, which involves running existing make-targets inside existing tool containers.  The effect of this is basically similar to "jobs" in github actions, or "agents" in jenkins.
    
    **Static Targets**:
    :  * Context-management tasks, such as 
            * [setting the active namespace](/k8s-tools/api#k8snamespacearg)
            * [start/stop for forwarded ports](/k8s-tools/api#kubefwdcontextmanagerarg)
            * [setting the active kube context](/k8s-tools/api#k8skubens)
        * Interactive debugging tasks, such as
            * [browsing logs](#placeholder)
            * [shelling into a new or existing pod inside some namespace](/k8s-tools/api#k8sshellarg)
            * [quick custom metrics displays](/k8s-tools/demos/metrics#interactive-workflows)
        * Reusable implementations for common cluster automation tasks, such as
            * [waiting for pods to get ready](/k8s-tools/api#k8s.wait)
            * [grabbing data to send it elsewhere](/k8s-tools/demos/cluster-lifecycle#interactive-workflows)
    
This page covers

### Tool Container Basics
<hr style="width:100%;border-bottom:3px solid black;">

Let's start with the basic stuff.  Commands in this section are examples of *generic target scaffolding* that is generated automatically for all the tool containers in the compose-file (including any containers that are user-defined later).  

Scaffold-generation and many other primitives are inherited from [`compose.mk`](https://robot-wranglers.github.io/compose.mk/), a more generic automation framework that `k8s.mk` extends.  Full documentation for scaffolding is out of scope here since it really isn't kubernetes specific.. but it's worth covering briefly.  See [the upstream docs](https://robot-wranglers.github.io/compose.mk/bridge/#target-scaffolding) for more details.

Other external documentation might be relevant.  For example, combining `k8s.mk` helpers with the `compose.mk` [workflow support](https://robot-wranglers.github.io/compose.mk/standard-lib/#workflow-support) is often useful, since you can easily accomplish things like retries, delayed actions, conditional actions, etc.  And by using the [`tux.*` API](https://robot-wranglers.github.io/compose.mk/embedded-tui/) you can send tasks, or groups of tasks, into panes on a TUI.

#### Listing Available Tools 
<hr style="width:95%;border-bottom:1px dashed black;">

```bash {.cli_example}
# Get a list of tool containers that are defined in k8s-tools.yml
$ ./k8s.mk k8s-tools.services
```
```ini {.cli_output}
failed
```

#### Shells & Task Dispatch
<hr style="width:95%;border-bottom:1px dashed black;">

What about shelling into a tool container to use commands directly?  We can do that and more, thanks to lots of generic targets that are generated for each container.

```bash {.cli_example}
# Interactive shell into the kubectl container
$ ./k8s.mk kubectl.shell
```
``` bash {.cli_output}
⇒ k8s-tools/kubectl.shell (...)
user@k8s:kubectl:/workspace$ 
```

```bash {.cli_example}
# Send commands to the rancher container
$ echo rancher --version | ./k8s.mk rancher.shell.pipe
```
``` bash {.cli_output}
rancher version v2.8.4
```

```bash {.cli_example}
# Dispatch any existing `make` target inside any given container
$ ./k8s.mk k3d.dispatch/io.draw.banner/hello-world
```
``` bash {.cli_output}
╔═══════════════════════════════════════════════════════════╗
║                        hello-world                        ║
╚═══════════════════════════════════════════════════════════╝
```

Dispatching tasks inside containers is a core feature of `compose.mk`[^3], basically allowing for something like "agents" in jenkins, or "jobs" in Github Actions without locking your automation up inside proprietary platforms or file formats.  

**The k8s-tools suite organizes around this idea,** describing tasks in `k8s.mk`, containers in `k8s-tools.yml`, and leveraging dispatch to accomplish "runs anywhere" style orchestration that you can then extend and compose inside your own scripts.

#### Script Dispatch
<hr style="width:95%;border-bottom:1px dashed black;">

The kinds of dispatch shown so far emphasize dispatching commands or make-tasks in containers, but it's often useful to dispatch a whole script.  The cleanest and clearest way to do this is using the `compose.bind.script` idiom.  Suppose you want to run something inside the `awscli` container as described in *k8s-tools.yml*.  

```Makefile {.snippet}
# Excerpted from the minio demo: 
#   /k8s-tools/demos/minio

..

minio.create_buckets:; $(call compose.bind.script, awscli)
define minio.create_buckets:
aws s3 ls
aws s3 mb s3://my-bucket
aws s3 ls
endef

..
```

#### Container Meta
<hr style="width:95%;border-bottom:1px dashed black;">

Besides command execution and dispatch, there are various commands that operate on the containers themselves.  These roughly follow the `docker compose ..` verbs.  See the main docs [here](https://robot-wranglers.github.io/compose.mk/bridge/#top-level-container-handles)

```bash {.cli_example}
# Force a rebuild of the helm container, even if it's cached.
$ force=1 ./k8s.mk helm.build
```
``` bash {.cli_output}
≣ services // helm // building.. 
[+] Building 13.7s 
=> [helm internal] load build definition from Dockerfile   
...
```

```bash {.cli_example}
# Show running kubefwd instances 
$ ./k8s.mk kubefwd.ps 
```
``` bash {.cli_output}
{
  "ID": "b19ba57e9435",
  "State": "running",
  "Status": "Up 28 minutes"
  ...
}
```

### Cluster CRUD
<hr style="width:100%;border-bottom:3px solid black;">

For creating, updating, and deleting clusters, the  [k3d API](/k8s-tools/api/#api-k3d) and the[minikube API](/k8s-tools/api/#api-minikube) are the main resources you're probably interested in.

Both backends use docker by default, which is required for `k3d`, but one of several options for `minikube`.  Generally `minikube` is smarter about caching by default, whereas `k3d` might be more like prod.  Jump to the [Cluster Lifecycle Demo](/k8s-tools/demos#demo-cluster-automation) for a more substantial demo with scripting, but read on for the basics.

```bash {.cli_example}
# Prep a blank kubeconfig 
$ touch mycluster.conf; chmod 711 mycluster.conf; export KUBECONFIG=./mycluster.conf 

# Bootstrap a named cluster
$ ./k8s.mk k3d.cluster.get_or_create/mycluster
```
```ini {.cli_output}
⇄ k3d.cluster.get_or_create/.. // Invoked from top; rerouting to tool-container 
⑆ k3d.cluster.get_or_create // mycluster 
Φ flux.if.then // flux.negate/k3d.has_cluster/mycluster .. true 
Φ flux.if.then // k3d.cluster.create/mycluster
⑆ k3d.cluster.create // mycluster 
+ k3d cluster create mycluster --servers 3 --agents 3 --api-port 6551 --volume /workspace/:/mycluster@all --wait
...
```

```bash {.cli_example}
# Check it out
$ ./k8s.mk k3d.cluster.list k3d.stat

# Wipe it out.  (Skip this if you're using it in the next demos)
$ ./k8s.mk k3d.cluster.delete/mycluster
```
```ini {.cli_output}
...
```

Interesting, right? A stand alone, project local cluster where even the nodes are dockerized, and without even installing `k3d` as a dependency. See the [Lifecycle Demo](/k8s-tools/demos/cluster-lifecycle) for a more complete example with scripting, or the [Multicluster Demo](/k8s-tools/demos/submariner) for an example with 2 clusters.

### Basic Platforming
<hr style="width:100%;border-bottom:3px solid black;">

For this section, `KUBECONFIG` should already be set, and you might want to use the cluster from the last section.

#### Helm
<hr style="width:95%;border-bottom:1px dashed black;">

With the k8s-tools suite, you can use `helm` directly but the simplest and most idempotent approach to installing things is usually via  <a style="" href="/k8s-tools/api/#ansiblehelm" >ansible.helm</a>.  *(See also the [upstream ansible docs](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/helm_module.html))*



We'll also need JSON input for this part, which `k8s.mk` inherits via [compose.mk](https://robot-wranglers.github.io/compose.mkstandard-lib/#structured-io), by way of the json.bash tool[^4].  As usual, no host dependencies are for this tool, or helm, or ansible, and everything is done via docker.  

The actual output is colored and easier to parse, but usage looks like this:

```bash {.cli_example}
# Test out the jb tool.
$ ./k8s.mk jb name=ahoy \
    release_namespace=default \
    chart_ref=hello-world \
    chart_repo_url="https://helm.github.io/examples"
```
```bash {.cli_output}
{ .. }
```

You can push the JSON to ansible by using pipes:

```bash {.cli_example}
# Pipe JSON to helm
$ ./k8s.mk jb name=ahoy \
    release_namespace=default \
    chart_ref=hello-world \
    chart_repo_url="https://helm.github.io/examples" \
  | ./k8s.mk ansible.helm
```
```bash {.cli_output}
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

Actually the helm commands in the last section can be turned into blocking ones by simply passing `wait=true`, but suppose you don't know this though, or the tool doesn't support it, or orchestration is much more complex.  In this case and in many others,  <a style="" href="/k8s-tools/api/#k8swait" >k8s.wait</a> is your best friend.

Changing the previous helm example to wait for the whole cluster to settle looks like this:

```bash {.cli_example}
$ ./k8s.mk jb name=ahoy \
    release_namespace=default \
    chart_ref=hello-world \
    chart_repo_url="https://helm.github.io/examples" \
  | ./k8s.mk ansible.helm k8s.wait
```

!!! closer_look "Closer Look"
    The JSON input sets defaults for the call to `ansible.helm`, and then `k8s.wait` runs to show a looping status display which indicates exactly what's still pending and what the cluster is up to.  Under the hood, it uses a colorized, looping version of krew's kubectl-sick-pods plugin[^2].

In a similar fashion you can use  <a style="" href="/k8s-tools/api/#k8snamespacewaitarg" >k8s.namespace.wait/&lt;namespace&gt;</a> to block on one particular namespace.


As [highlighted elsewhere](#), the nature of Makefile ensures that the `k8s.mk` CLI is essentially one-to-one with the API.  

Thanks to that, **tools like `k8s.wait` aren't just commands, but also a powerful synchronization primitive in scripting**, especially when used as target prerequisites.  Consider the following snippet of Makefile:

```Makefile {.language-makefile .snippet}
# Create and enter the `my_platform` namespace before we do anything
setup.platform: k8s.kubens.create/my_platform
	kubectl apply ...

# Blocks on `my_platform` bootstrap completing, then sets
# the `my_platform` namespace as default inside the target body.
setup.app: k8s.namespace.wait/my_platform k8s.kubens/my_platform
	kubectl apply ...

bootstrap: setup.platform setup.logging setup.monitoring setup.app
```

Of course you could do this in pure shell or a variety of other ways, but preferring a Makefile tends to keep things organized.  First, we retained the ability to execute every piece of our cluster bootstrap individually, rather than being stuck with some kind of top-to-bottom execution of everything.  Second, we avoided `--namespace` arguments inside the target-body.

Much more advanced stuff is possible by combining make's [native support for parallelism](https://www.gnu.org/software/make/manual/html_node/Parallel.html) and its own [synchronization primitives](https://www.gnu.org/software/make/manual/html_node/Parallel-Disable.html).


<hr style="width:100%;border-bottom:3px solid black;">
[^1]: [About homoiconicity in compose.mk](https://robot-wranglers.github.io/compose.mk/language/#homoiconic)
[^4]: [https://github.com/h4l/json.bash](https://github.com/h4l/json.bash), [compose.mk://container-dispatch](https://robot-wranglers.github.io/compose.mk/standard-lib#structured-io)
[^2]: [https://github.com/alecjacobs5401/kubectl-sick-pods](https://github.com/alecjacobs5401/kubectl-sick-pods)
[^3]: [compose.mk://container-dispatch](https://robot-wranglers.github.io/compose.mk/container-dispatch)
