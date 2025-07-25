#!/usr/bin/env -S make -f
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# Demonstrates using kubetail directly, starting the log browser in the 
# foreground or the background, or calling kubetail programmatically.
#
# See here[1] for more discussion, here[2] for official kubetail CLI docs.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/kubetail
#   [2] https://www.kubetail.com/docs/cli/commands/logs
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include demos/fission.mk

# Display various logs.  Usage: kubetail/<namespace>/<kind>/filter
logs.basic: kubetail/fission/deployments/* \
	kubetail/fission/jobs/* kubetail/fission/pods/*

# Faster version of the above, pass all log requests at once.
logs.alt: kubetail/fission/deployments/*,fission/jobs/*,fission/pods/*

# Directly interact with kubetail
logs.custom: k8s.dispatch/self.logs.custom 
self.logs.custom:
	kubetail --help

# Two ways to launch the kubetail web-UI for this cluster context.
serve: kubetail.serve
	@# By default, `kubetail.serve` is blocking.
	@# If you use it from `__main__`, use it at the end!

serve.bg: kubetail.serve.bg
	@# A non-blocking version is also available, but remember to 
	@# stop it, because it won't be handled by cluster shutdown.
