## Automation With k8s.mk
<hr style="width:100%;border-bottom:3px solid black;">

`k8s.mk` can help to create project automation APIs that do stuff with the tool-containers that are described in k8s-tools.yml, and includes lots of general helper targets for working with Kubernetes.  



The focus is on simplifying a few categories of frequent challenges:

1. **Reusable implementations for common cluster automation tasks,** like [waiting for pods to get ready](/k8s-tools/api#k8s.wait)
1. **Context-management tasks,** (like [setting the currently active namespace](/k8s-tools/api#k8snamespacearg))
1. **Interactive debugging tasks,** (like [shelling into a new or existing pod inside some namespace](/k8s-tools/api#k8sshellarg))

The full API is [here](/k8s-tools/api/#api-k8smk), and the [Cluster Lifecycle Demo](/k8s-tools/demos#demo-cluster-automation) includes a walk-through of using it from your own project automation.  

By combining these tools with compose.mk's [`flux.*` API](https://robot-wranglers.github.io/compose.mk//api#api-flux) you can describe workflows, and using the [`tux.*` API](https://robot-wranglers.github.io/compose.mk//api#api-tux) you can send tasks, or groups of tasks, into panes on a TUI.

### Automation APIs over Tool Containers
<hr style="width:100%;border-bottom:3px solid black;">

What *is* an automation API over a tool container anyway?  

As an example, let's consider the [`k8s.get` target](/k8s-tools/api/#k8sget), which you might use like this:

```bash
# Usage: k8s.get/<namespace>/<kind>/<name>/<filter>
$ KUBECONFIG=.. ./k8s.mk k8s.get/argo-events/svc/webhook-eventsource-svc/.spec.clusterIP

# roughly equivalent to:
$ kubectl get $${kind} $${name} -n $${namespace} -o json | jq -r ..filter.."
```

The first command has no host requirements for `kubectl` or `jq`, but uses both via docker.  

Similarly, the [`helm.install` target](/k8s-tools/api#helm.install) works as you'd expect but does not require `helm` (and plus it's a little more idempotent than using `helm` directly).  Meanwhile `k8s.mk k9s/<namespace>` works like `k9s --namespace` does, but doesn't require k9s.

Many of these targets are fairly simple wrappers, but just declaring them accomplishes several things at once.

The typical `k8s.mk` entrypoint is:

1. CLI friendly, for interactive contexts, as above
1. API friendly, for more programmatic use, as part of the prereqs or the body for other project automation
1. Workflow friendly, either as part of `make`'s native DAG processing, or via [flux](/api#api-flux).
1. Potentially a TUI element, via the [embedded TUI](/#embedded-tui) and [tux](/api#tux).
1. Context-agnostic, generally using tools directly if available or falling back to docker when necessary.

Some targets like [`k8s.shell`](/k8s-tools/api/#k8sshell) or [`kubefwd.[start|stop|restart]`](/k8s-tools/api/#kubefwd) are more composite than simple wrappers, and achieve more complex behaviour by orchestrating 1 or more commands across 1 or more containers.  See also the [ansible wrapper](/k8s-tools/api#api-ansible), which exposes a subset of `ansible` without all the overhead of inventories & config.

If you want you can always to stream arbitrary commands or scripts into these containers more directly, via [the Make/Compose bridge](https://robot-wranglers.github.io/compose.mk//bridge), or write your own targets that run inside those containers.  But the point of `k8s.mk` is to ignore more of the low-level details more of the time, and start to compose things.  For example, here's a one-liner that creates a namespace, adds a label to it, launches a pod there, and shells into it:

```bash 
$ pod=`uuidgen` \
&& namespace=testing \
&& ./k8s.mk \
    k8s.kubens.create/${namespace} \ \
    k8s.namespace.label/$${namespace}/mylabel/value
    k8s.test_harness/${namespace}/${pod} \
    k8s.namespace.wait/${namespace} \
    k8s.shell/${namespace}/${pod}
```

### But Why?
<hr style="width:100%;border-bottom:3px solid black;">

There's many reasons why you might want these capabilities if you're working with cluster-lifecycle automation.  People tend to have strong opions about this topic, and it's kind of a long story.  The short version is this: 

* Tool versioning, idempotent operations, & deterministic cluster bootstrapping are all hard problems, but not really the problems we *want* to be working on.
* IDE-plugins and desktop-distros that offer to manage Kubernetes are hard for developers to standardize on, and tend to resist automation.  
* Project-local clusters are much-neglected, but also increasingly important aspects of project testing and overall developer-experience.  
* Ansible/Terraform are great, but they have to be versioned themselves, and aren't necessarily a great fit for this type of problem.  


