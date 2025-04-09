# HyperFlow K8S monitoring

```
helm upgrade --dependency-update -i hf-obs charts/hyperflow-observability
```

## Open opensearch dashboards

```
kubectl port-forward svc/hf-obs-opensearch-dashboards 5601:5601
```

Navigate to
http://localhost:5601/

Go to Dashboards Management -> Index Patterns

create index patterns
- hyperflow_traces
- hyperflow_metrics
- hyperflow_logs

Go to Discover and choose one of new index patterns as source
