import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { ApiError, BackendErrorBody } from './models/api-error.model';

export const apiErrorInterceptor: HttpInterceptorFn = (req, next) => {
  return next(req).pipe(
    catchError((response: unknown) => {
      if (response instanceof HttpErrorResponse) {
        const body = response.error as BackendErrorBody | null;

        let message = `HTTP ${response.status}`;
        let code: string | undefined;

        if (body) {
          if (Array.isArray(body.details) && body.details.length > 0) {
            message = body.details.join('; ');
          } else if (body.message) {
            message = body.message;
          } else if (body.error) {
            message = body.error;
          }
          code = body.code;
        } else if (response.message) {
          message = response.message;
        }

        return throwError(() => new ApiError(response.status, message, code));
      }
      return throwError(() => response);
    })
  );
};