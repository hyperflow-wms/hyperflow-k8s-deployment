#!/usr/bin/env -S python3 -I
"""Helm post-renderer for the Montage test in namespace hyperflow-devel.

Helm passes the rendered manifests on stdin and installs what this prints.
It removes the hyperflow-engine chart's ClusterRoleBinding (cluster-admin
for every service account); the engine gets a namespaced Role from
hyperflow-k8s-deployment/cluster/montage-devel-prereqs.yaml instead.

It refuses, with exit status 1, any other cluster-scoped object and any
object that names a namespace other than hyperflow-devel, so the release can
create nothing outside that namespace. Documents are passed through as
rendered, not re-serialised.

Used with Helm 3; needs python3 with PyYAML:
  helm upgrade --install ... --post-renderer cluster/drop-cluster-role-binding.py
"""

import re
import sys

import yaml

NAMESPACE = "hyperflow-devel"
DROP = {"ClusterRoleBinding"}
CLUSTER_SCOPED = {
    "ClusterRole", "ClusterRoleBinding", "Namespace", "PersistentVolume",
    "PriorityClass", "StorageClass", "CustomResourceDefinition",
    "MutatingWebhookConfiguration", "ValidatingWebhookConfiguration",
}


def main():
    chunks = re.split(r"(?m)^---[ \t]*\n?", sys.stdin.read())
    kept, dropped, errors = [], [], []
    for chunk in chunks:
        try:
            doc = yaml.safe_load(chunk)
        except yaml.YAMLError as err:
            errors.append("cannot parse a rendered document: %s" % err)
            continue
        if not doc:
            continue
        kind = doc.get("kind")
        meta = doc.get("metadata") or {}
        name = "%s/%s" % (kind, meta.get("name"))
        if kind in DROP:
            dropped.append(name)
            continue
        if kind in CLUSTER_SCOPED:
            errors.append("cluster-scoped object not allowed: " + name)
        ns = meta.get("namespace")
        if ns not in (None, NAMESPACE):
            errors.append("%s names namespace %s" % (name, ns))
        kept.append(chunk.strip("\n"))
    if errors:
        for err in errors:
            print("post-renderer: " + err, file=sys.stderr)
        sys.exit(1)
    sys.stdout.write("---\n" + "\n---\n".join(kept) + "\n")
    print("post-renderer: dropped " + (", ".join(dropped) or "nothing"), file=sys.stderr)


main()
