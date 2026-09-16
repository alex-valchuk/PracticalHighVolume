export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly code?: string
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export interface BackendErrorBody {
  error?: string;
  code?: string;
  message?: string;
  details?: string[];
}