import http from "k6/http";
import { check } from "k6";

function positiveInteger(name, fallback) {
  const parsed = Number.parseInt(__ENV[name] || fallback, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}

const baseUrl = (__ENV.BASE_URL || "").replace(/\/+$/, "");
if (baseUrl.length === 0) {
  throw new Error("BASE_URL is required");
}
if (!baseUrl.startsWith("https://") && __ENV.ALLOW_INSECURE_LOCAL !== "true") {
  throw new Error("BASE_URL must use HTTPS outside an explicitly local run");
}

let accessTokens;
try {
  accessTokens = JSON.parse(__ENV.ACCESS_TOKENS_JSON || "[]");
} catch {
  throw new Error("ACCESS_TOKENS_JSON must be a JSON array");
}
if (
  !Array.isArray(accessTokens) ||
  accessTokens.length === 0 ||
  accessTokens.some((token) => typeof token !== "string" || token.length < 32)
) {
  throw new Error("ACCESS_TOKENS_JSON must contain short-lived access tokens");
}

const publicRate = positiveInteger("PUBLIC_RATE", "5");
const stateRate = positiveInteger("STATE_RATE", "25");
const duration = __ENV.DURATION || "2m";
const preAllocatedVus = positiveInteger(
  "PREALLOCATED_VUS",
  Math.max(10, stateRate).toString(),
);
const maxVus = positiveInteger(
  "MAX_VUS",
  Math.max(preAllocatedVus, stateRate * 3).toString(),
);

export const options = {
  discardResponseBodies: true,
  scenarios: {
    authoritative_reads: {
      duration,
      exec: "authoritativeReads",
      executor: "constant-arrival-rate",
      maxVUs: maxVus,
      preAllocatedVUs: preAllocatedVus,
      rate: stateRate,
      timeUnit: "1s",
    },
    public_probe: {
      duration,
      exec: "publicProbe",
      executor: "constant-arrival-rate",
      maxVUs: 5,
      preAllocatedVUs: 2,
      rate: publicRate,
      timeUnit: "1s",
    },
  },
  thresholds: {
    checks: ["rate>0.99"],
    dropped_iterations: ["count==0"],
    "http_req_duration{operation:billing_entitlements}": ["p(95)<750", "p(99)<1500"],
    "http_req_duration{operation:health_live}": ["p(95)<100", "p(99)<250"],
    "http_req_duration{operation:state_snapshot}": ["p(95)<750", "p(99)<1500"],
    "http_req_duration{operation:sync_snapshot}": ["p(95)<1000", "p(99)<2000"],
    "http_req_failed{scenario:authoritative_reads}": ["rate<0.01"],
    "http_req_failed{scenario:public_probe}": ["rate<0.001"],
  },
};

function request(path, operation) {
  const token = accessTokens[(__VU + __ITER) % accessTokens.length];
  return http.get(`${baseUrl}${path}`, {
    headers: {
      authorization: `Bearer ${token}`,
    },
    tags: {
      name: path,
      operation,
    },
  });
}

export function publicProbe() {
  const response = http.get(`${baseUrl}/health/live`, {
    tags: {
      name: "/health/live",
      operation: "health_live",
    },
  });
  check(response, {
    "health live status is 200": (result) => result.status === 200,
  });
}

export function authoritativeReads() {
  const selection = __ITER % 3;
  const response =
    selection === 0
      ? request("/v1/me", "state_snapshot")
      : selection === 1
        ? request("/v1/sync/snapshot", "sync_snapshot")
        : request("/v1/billing/entitlements", "billing_entitlements");
  check(response, {
    "authoritative read status is 200": (result) => result.status === 200,
  });
}
