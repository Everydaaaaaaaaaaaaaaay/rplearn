import "dotenv/config";
import { FastifyOtelInstrumentation } from "@fastify/otel";
import type { Span } from "@opentelemetry/api";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-proto";
import { HttpInstrumentation } from "@opentelemetry/instrumentation-http";
import {
  UndiciInstrumentation,
  type UndiciRequest,
} from "@opentelemetry/instrumentation-undici";
import { defaultResource, resourceFromAttributes } from "@opentelemetry/resources";
import { NodeSDK } from "@opentelemetry/sdk-node";
import {
  AlwaysOffSampler,
  ParentBasedSampler,
  TraceIdRatioBasedSampler,
} from "@opentelemetry/sdk-trace";
import {
  ATTR_DEPLOYMENT_ENVIRONMENT_NAME,
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_NAMESPACE,
  ATTR_SERVICE_VERSION,
  ATTR_URL_FULL,
  ATTR_URL_PATH,
  ATTR_URL_QUERY,
} from "@opentelemetry/semantic-conventions";
import {
  pathFromTelemetryUrl,
  resolveTelemetrySettings,
  sanitizedTelemetryPath,
} from "./config/telemetry.js";

const INTERNAL_PATHS = new Set(["/health/live", "/health/ready", "/internal/metrics"]);

function sanitizeSpanUrl(span: Span, path: string, origin: string): void {
  span.setAttribute(ATTR_URL_FULL, `${origin.replace(/\/+$/, "")}${path}`);
  span.setAttribute(ATTR_URL_PATH, path);
  span.setAttribute(ATTR_URL_QUERY, "");
}

const settings = resolveTelemetrySettings();
let sdk: NodeSDK | undefined;
let shutdownPromise: Promise<void> | undefined;

if (settings.enabled) {
  const ratioSampler = new TraceIdRatioBasedSampler(settings.sampleRatio);
  sdk = new NodeSDK({
    instrumentations: [
      new HttpInstrumentation({
        disableOutgoingRequestInstrumentation: true,
        ignoreIncomingRequestHook: (request) =>
          INTERNAL_PATHS.has(pathFromTelemetryUrl(request.url)),
        requestHook: (span) => {
          // The lower HTTP span cannot see Fastify's route template yet. Keep
          // it identifier-free; the child Fastify span carries the route.
          sanitizeSpanUrl(span, "/", "https://lingotrip.internal");
        },
      }),
      new UndiciInstrumentation({
        requestHook: (span, request: UndiciRequest) => {
          const origin = new URL(request.origin).origin;
          sanitizeSpanUrl(span, sanitizedTelemetryPath(request.path), origin);
        },
        requireParentforSpans: true,
      }),
      new FastifyOtelInstrumentation({
        ignorePaths: ({ url }) => INTERNAL_PATHS.has(pathFromTelemetryUrl(url)),
        instrumentHooks: false,
        recordExceptions: false,
        registerOnInitialization: true,
        requestHook: (span, request) => {
          sanitizeSpanUrl(
            span,
            sanitizedTelemetryPath(request.routeOptions.url),
            "https://lingotrip.internal",
          );
        },
      }),
    ],
    resource: defaultResource().merge(
      resourceFromAttributes({
        [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: process.env.NODE_ENV ?? "development",
        [ATTR_SERVICE_NAME]: settings.serviceName,
        [ATTR_SERVICE_NAMESPACE]: "lingotrip",
        [ATTR_SERVICE_VERSION]: settings.serviceVersion,
      }),
    ),
    sampler: new ParentBasedSampler({
      remoteParentNotSampled: new AlwaysOffSampler(),
      remoteParentSampled: ratioSampler,
      root: ratioSampler,
    }),
    traceExporter: new OTLPTraceExporter({
      timeoutMillis: settings.exportTimeoutMs,
      url: settings.endpoint,
    }),
  });
  sdk.start();
}

export async function shutdownTelemetry(): Promise<void> {
  if (sdk === undefined) {
    return;
  }
  shutdownPromise ??= sdk.shutdown();
  await shutdownPromise;
}
