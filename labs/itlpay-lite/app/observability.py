"""Metrics, structured logs and traces for ITL Pay Lite (Module 11).

- Metrics (topic 11.1): Prometheus format at GET /metrics. Request counts and latency per route *template*
  (/api/v1/transfers/{tid}, never the real ID, so the number of time series stays small), and business counters.
- Logs (topic 11.2): one JSON object per line when LOG_FORMAT=json, with the trace ID when a trace is active, so a
  log line and its trace can be found from each other.
- Traces (topic 11.2): OpenTelemetry, only when OTEL_EXPORTER_OTLP_ENDPOINT is set (for example
  http://otel-collector:4318). The service name comes from OTEL_SERVICE_NAME (default itlpay-lite).
"""
from __future__ import annotations

import json
import logging
import os
import time

from fastapi import FastAPI, Request, Response
from opentelemetry import trace
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

REQUESTS = Counter("http_requests_total", "HTTP requests handled", ["method", "route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "Time to handle an HTTP request", ["method", "route"],
                    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5))
TRANSFERS = Counter("itlpay_transfers_total", "Transfer requests by result", ["result"])
TRANSFERRED = Counter("itlpay_transferred_kobo_total", "Money moved by completed transfers, in kobo")

tracer = trace.get_tracer("itlpay")


class JsonFormatter(logging.Formatter):
    """One JSON object per line: easy for Loki, CloudWatch, Azure Monitor and Cloud Logging to parse."""

    def format(self, record: logging.LogRecord) -> str:
        entry = {"time": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"), "level": record.levelname,
                 "logger": record.name, "message": record.getMessage(), "service": os.environ.get("OTEL_SERVICE_NAME", "itlpay-lite"),
                 "env": os.environ.get("APP_ENV", "local")}
        ctx = trace.get_current_span().get_span_context()
        if ctx.is_valid:
            entry["trace_id"] = format(ctx.trace_id, "032x")
            entry["span_id"] = format(ctx.span_id, "016x")
        if record.exc_info:
            entry["error"] = self.formatException(record.exc_info)
        return json.dumps(entry)


def setup_logging() -> None:
    handler = logging.StreamHandler()
    if os.environ.get("LOG_FORMAT", "text") == "json":
        handler.setFormatter(JsonFormatter())
    else:
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), handlers=[handler], force=True)


def setup_tracing(app: FastAPI) -> bool:
    if not os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"):
        return False
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    provider = TracerProvider(resource=Resource.create({
        "service.name": os.environ.get("OTEL_SERVICE_NAME", "itlpay-lite"),
        "deployment.environment.name": os.environ.get("APP_ENV", "local")}))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))  # reads OTEL_EXPORTER_OTLP_* variables
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app, excluded_urls="health,metrics")
    return True


def setup_metrics(app: FastAPI) -> None:
    @app.get("/metrics", include_in_schema=False)
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.middleware("http")
    async def record(request: Request, call_next):
        start = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            route = request.scope.get("route")
            path = getattr(route, "path", None) or "unmatched"  # the template, not the URL
            if path != "/metrics":
                REQUESTS.labels(request.method, path, str(status)).inc()
                LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
