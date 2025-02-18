rm -f compose.mk k8s.mk
rm -f k8s-tools.yml
(ls ${KUBECONFIG} > /dev/null 2>/dev/null || touch ${KUBECONFIG})  \
&& (cp ../*.yml . ) \
&& (cp ../*.mk .)