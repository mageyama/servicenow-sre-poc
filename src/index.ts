import express, { Request, Response } from "express";

const app = express();
const PORT: number = Number(process.env.PORT) || 8080;

const ERROR_MESSAGES: readonly string[] = [
  "Database connection timeout",
  "Redis cache unavailable",
  "Upstream service returned 502",
  "Memory limit exceeded",
  "Disk I/O error on /var/data",
  "TLS handshake failed with auth-service",
  "Message queue consumer lag exceeded threshold",
  "Config server unreachable",
  "DNS resolution failed for internal.svc.cluster.local",
  "Circuit breaker tripped for payment-service",
] as const;

interface HealthResponse {
  status: string;
  service: string;
}

interface ErrorResponse {
  error: string;
}

app.get("/", (_req: Request, res: Response<HealthResponse>) => {
  res.json({ status: "ok", service: "servicenow-sre-poc" });
});

app.get("/error", (_req: Request, res: Response<ErrorResponse>) => {
  const message = ERROR_MESSAGES[Math.floor(Math.random() * ERROR_MESSAGES.length)];
  console.error(JSON.stringify({ severity: "ERROR", message }));
  res.status(500).json({ error: message });
});

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});
