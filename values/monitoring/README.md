# HyperFlow K8S monitoring


## Run opensearch stack
```
helm install opensearch -f ./opensearch/opensearch-values.yaml  opensearch/opensearch
helm install opensearch-dashboards -f ./opensearch/dashboards-values.yaml opensearch/opensearch-dashboards
helm install dataprepper -f ./opensearch/dataprepper-values.yaml opensearch/data-prepper
```

## Run otel stack
```
helm install opentelemetry-collector -f ./otel/collector-values.yaml open-telemetry/opentelemetry-collector
```

## Open opensearch dashboards

```
kubectl port-forward svc/opensearch-dashboards 5601:5601
```

Navigate to
http://localhost:5601/

Go to Dashboards Management -> Index Patterns

create index patterns
- hyperflow_traces
- hyperflow_metrics
- hyperflow_logs

Go to Discover and choose one of new index patterns as source
