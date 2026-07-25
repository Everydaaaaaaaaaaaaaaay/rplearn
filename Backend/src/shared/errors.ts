export type PublicErrorBody = Readonly<{
  code: string;
  details?: unknown;
  message: string;
  requestId: string;
}>;

export class AppError extends Error {
  readonly code: string;
  readonly details?: unknown;
  readonly expose: boolean;
  readonly statusCode: number;

  constructor(options: {
    cause?: unknown;
    code: string;
    details?: unknown;
    expose?: boolean;
    message: string;
    statusCode: number;
  }) {
    super(options.message, { cause: options.cause });
    this.name = "AppError";
    this.code = options.code;
    this.details = options.details;
    this.expose = options.expose ?? options.statusCode < 500;
    this.statusCode = options.statusCode;
  }
}
