from fastapi import FastAPI, Depends, HTTPException, status, Query
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.responses import FileResponse
from fastapi.responses import StreamingResponse
import requests
import json
import os
from typing import List, Dict, Tuple

app = FastAPI()

# --- KONFIGURACJA ---
OPENSEARCH_URL = "http://localhost:9200"
SCROLL_TIME = "5m"
SCROLL_SIZE = 5000
LOGS_INDEX = "hyperflow_logs"
METRICS_INDEX = "hyperflow_metrics"

# --- SECURITY DEPENDENCY ---
security = HTTPBasic()

def get_auth(credentials: HTTPBasicCredentials = Depends(security)) -> Tuple[str, str]:
    if not credentials.username or not credentials.password:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Brak credentials",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username, credentials.password

# --- WSPÓLNE FUNKCJE SCROLLINGU ---

def perform_initial_scroll(index: str, payload: Dict, auth: Tuple[str, str]) -> Dict:
    return requests.get(
        f"{OPENSEARCH_URL}/{index}/_search?scroll={SCROLL_TIME}",
        json=payload,
        auth=auth
    ).json()

def perform_scroll(scroll_id: str, auth: Tuple[str, str]) -> Dict:
    return requests.post(
        f"{OPENSEARCH_URL}/_search/scroll",
        json={"scroll": SCROLL_TIME, "scroll_id": scroll_id},
        auth=auth
    ).json()

def scroll_by_query(index: str, query_body: Dict, auth: Tuple[str, str]) -> List[Dict]:
    """
    Uniwersalna funkcja scrollująca po zadanym body zapytania.
    Zwraca listę dokumentów (hits).
    """
    all_hits = []
    payload = {"size": SCROLL_SIZE, "query": query_body}

    resp = perform_initial_scroll(index, payload, auth)
    scroll_id = resp.get("_scroll_id")
    hits = resp.get("hits", {}).get("hits", [])
    all_hits.extend(hits)

    while hits:
        resp = perform_scroll(scroll_id, auth)
        scroll_id = resp.get("_scroll_id")
        hits = resp.get("hits", {}).get("hits", [])
        all_hits.extend(hits)

    return all_hits

@app.get("/logs/by-workflow/{workflow_id}")
def get_logs_by_workflow(
    workflow_id: str,
    auth: Tuple[str, str] = Depends(get_auth)
):
    query_body = {"term": {"log.attributes.workflowId.keyword": workflow_id}}
    hits = scroll_by_query(LOGS_INDEX, query_body, auth)

    file_name = f"logs_{workflow_id}.json"
    with open(file_name, "w", encoding="utf-8") as f:
        json.dump([h["_source"] for h in hits], f, ensure_ascii=False, indent=2)

    return {"message": "Zapisano logi", "file": os.path.abspath(file_name), "count": len(hits)}


@app.get("/logs/by-date")
def get_logs_by_date(
    start_date: str = Query(..., description="Start date ISO (np. 2025-05-01T00:00:00Z)"),
    end_date:   str = Query(..., description="End   date ISO (np. 2025-05-05T23:59:59Z)"),
    auth: Tuple[str, str] = Depends(get_auth)
):
    query_body = {
        "range": {
            "time": {
                "gte": start_date,
                "lte": end_date,
                "format": "strict_date_optional_time"
            }
        }
    }
    hits = scroll_by_query(LOGS_INDEX, query_body, auth)

    file_name = f"logs_{start_date}_{end_date}.json".replace(":", "-")
    with open(file_name, "w", encoding="utf-8") as f:
        json.dump([h["_source"] for h in hits], f, ensure_ascii=False, indent=2)

    return {"message": "Zapisano logi", "file": os.path.abspath(file_name), "count": len(hits)}


@app.get("/metrics/by-workflow/{workflow_id}")
def get_metrics_by_workflow(
    workflow_id: str,
    auth: Tuple[str, str] = Depends(get_auth)
):
    query_body = {"term": {"metric.attributes.workflowId.keyword": workflow_id}}
    hits = scroll_by_query(METRICS_INDEX, query_body, auth)

    file_name = f"metrics_{workflow_id}.json"
    with open(file_name, "w", encoding="utf-8") as f:
        json.dump([h["_source"] for h in hits], f, ensure_ascii=False, indent=2)

    return {"message": "Zapisano metryki", "file": os.path.abspath(file_name), "count": len(hits)}


@app.get("/metrics/by-date")
def get_metrics_by_date(
    start_date: str = Query(..., description="Start date ISO (np. 2025-05-01T00:00:00Z)"),
    end_date:   str = Query(..., description="End   date ISO (np. 2025-05-05T23:59:59Z)"),
    auth: Tuple[str, str] = Depends(get_auth)
):
    must_clause = {
        "range": {
            "time": {
                "gte": start_date,
                "lte": end_date,
                "format": "strict_date_optional_time"
            }
        }
    }
    query_body = {"bool": {"must": [must_clause]}}
    hits = scroll_by_query(METRICS_INDEX, query_body, auth)

    file_name = f"metrics_{start_date}_{end_date}.json".replace(":", "-")
    with open(file_name, "w", encoding="utf-8") as f:
        json.dump([h["_source"] for h in hits], f, ensure_ascii=False, indent=2)

    return FileResponse(
        path=file_name,
        filename=os.path.basename(file_name),
        media_type="application/json"
    )


@app.get("/metrics/filter/by-workflow/{workflow_id}")
def filter_metrics_by_workflow(
    workflow_id: str,
    name: List[str] = Query(
        None,
        description="Filtruj po polu `name`; np. ?name=cpu-usage&name=memory-usage"
    ),
    auth: Tuple[str, str] = Depends(get_auth)
):
    must_clauses = [
        {"term": {"metric.attributes.workflowId.keyword": workflow_id}}
    ]
    if name:
        must_clauses.append({"terms": {"name.keyword": name}})

    query_body = {"bool": {"must": must_clauses}}
    hits = scroll_by_query(METRICS_INDEX, query_body, auth)

    file_name = f"metrics_filtered_{workflow_id}.json"
    with open(file_name, "w", encoding="utf-8") as f:
        json.dump([h["_source"] for h in hits], f, ensure_ascii=False, indent=2)

    return {"message": "Zapisano przefiltrowane metryki", "file": os.path.abspath(file_name), "count": len(hits)}


@app.get("/metrics/filter/by-date")
def filter_metrics_by_date(
    start_date: str = Query(..., description="Start date ISO (np. 2025-05-01T00:00:00Z)"),
    end_date:   str = Query(..., description="End   date ISO (np. 2025-05-05T23:59:59Z)"),
    name: List[str] = Query(None, description="Filtruj po polu `name`; np. ?name=cpu-usage&name=memory-usage"),
    task_type: List[str] = Query(None, description="Filtruj po `metric.attributes.name`; ..."),
    auth: Tuple[str, str] = Depends(get_auth)
):
    must_clauses = [
        {
            "range": {
                "time": {
                    "gte": start_date,
                    "lte": end_date,
                    "format": "strict_date_optional_time"
                }
            }
        }
    ]
    if name:
        must_clauses.append({"terms": {"name.keyword": name}})

    if task_type:
            must_clauses.append({"terms": {"metric.attributes.name.keyword": task_type}})

    query_body = {"bool": {"must": must_clauses}}
    hits = scroll_by_query(METRICS_INDEX, query_body, auth)

    file_name = f"metrics_filtered_{start_date}_{end_date}.json".replace(":", "-")
    with open(file_name, "w", encoding="utf-8") as f:
        json.dump([h["_source"] for h in hits], f, ensure_ascii=False, indent=2)

    return FileResponse(
        path=file_name,
        filename=os.path.basename(file_name),
        media_type="application/json"
    )

@app.get("/logs/by-date/stream")
def stream_logs_by_date(
    start_date: str = Query(..., description="Start date ISO (np. 2025-05-01T00:00:00Z)"),
    end_date: str = Query(..., description="End date ISO (np. 2025-05-05T23:59:59Z)"),
    auth: Tuple[str, str] = Depends(get_auth)
):
    query_body = {
            "range": {
                "time": {
                    "gte": start_date,
                    "lte": end_date,
                    "format": "strict_date_optional_time"
                }
            }
        }
    hits = scroll_by_query(LOGS_INDEX, query_body, auth)

    def generate():
        for hit in hits:
            yield json.dumps(hit["_source"]) + "\n"

    return StreamingResponse(generate(), media_type="application/jsonlines")

@app.get("/metrics/by-date/stream")
def stream_metrics_by_date(
    start_date: str = Query(..., description="Start date ISO (np. 2025-05-01T00:00:00Z)"),
    end_date: str = Query(..., description="End date ISO (np. 2025-05-05T23:59:59Z)"),
    auth: Tuple[str, str] = Depends(get_auth)
):
    must_clause = {
            "range": {
                "time": {
                    "gte": start_date,
                    "lte": end_date,
                    "format": "strict_date_optional_time"
                }
            }
        }
    query_body = {"bool": {"must": [must_clause]}}
    hits = scroll_by_query(METRICS_INDEX, query_body, auth)

    def generate():
        for hit in hits:
            yield json.dumps(hit["_source"]) + "\n"

    return StreamingResponse(generate(), media_type="application/jsonlines")

