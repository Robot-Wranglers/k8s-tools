#!/usr/bin/env -S make -f
# Working with Tilt and Tiltfiles, part 2.
# Cluster Management + Inlined Tiltfile
#   
# See the documentation here[1] for more discussion.
# This demo ships with the `k8s-tools` repo and runs as part of the test-suite.
#
# USAGE: 
#	./demos/tilt-inlined.mk clean create deploy.inlined test
#
# REF:
#   [1] https://robot-wranglers.github.io/k8s-tools/demos/tilt/
#   [2] https://docs.tilt.dev/api.html
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include demos/tilt.mk

# You can use an ephemeral tmpfile here instead, but anything that's 
# cleaned up when the process exits tends to confuse `tilt` because 
# it's tracking changes for the file.
tiltfile=.tmp.Tiltfile

deploy.inlined: stage/deploy
	${mk.def.read}/Tiltfile > ${tiltfile} \
	&& ${make} tilt.serve/${tiltfile} io.wait/7

define Tiltfile
print("🚀 Inlined Tiltfile")

## Must match the cluster-name that minikube is using.
allow_k8s_contexts('tilt')

os.putenv('CMK_INTERNAL', '0')

local_resource(
    'k8s.mk',
    cmd='''
# Currently in the demos/data folder 
# (This is relative to Tiltfile location)
pwd

# Run commands from project Makefile
./demos/tilt.mk flux.ok
./demos/tilt.mk tilt.ps

# Use k8s.mk directly, in stand-alone mode.
./k8s.mk k8s.stat
''',
    auto_init=False, labels=['cmk'],
    trigger_mode=TRIGGER_MODE_MANUAL,
)
include('demos/data/Tiltfile')
endef