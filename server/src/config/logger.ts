import winston from 'winston';
import path from 'path';
import * as Sentry from '@sentry/node';

const maskFields = new Set(['password', 'password_hash', 'token', 'cvv', 'pan', 'card_number', 'client_secret', 'secret', 'pin']);

function maskSensitiveData(obj: any): any {
  if (!obj || typeof obj !== 'object') return obj;
  if (obj instanceof Error) return obj; // Preserve original error object

  if (Array.isArray(obj)) {
    return obj.map(maskSensitiveData);
  }

  const masked: any = {};
  for (const key of Object.keys(obj)) {
    const val = obj[key];
    if (maskFields.has(key.toLowerCase())) {
      masked[key] = '***MASKED***';
    } else if (typeof val === 'object' && val !== null) {
      masked[key] = maskSensitiveData(val);
    } else {
      masked[key] = val;
    }
  }
  return masked;
}

const maskFormat = winston.format((info) => {
  if (typeof info.message === 'string') {
    info.message = info.message.replace(/(password|cvv|pan|client_secret|pin|secret)=([^&\s]+)/gi, '$1=***MASKED***');
  }
  // Mutate string-keyed metadata in place. Returning a cloned object drops
  // Winston's Symbol.for('level') / Symbol.for('message') fields, which makes
  // file transports silently discard records while console output may remain.
  for (const key of Object.keys(info)) {
    if (key === 'message') continue;
    const value = info[key];
    info[key] = maskFields.has(key.toLowerCase())
      ? '***MASKED***'
      : maskSensitiveData(value);
  }
  return info;
})();

const logFormat = winston.format.combine(
  maskFormat,
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  winston.format.json()
);

import Transport from 'winston-transport';

class SentryTransport extends Transport {
  constructor(opts?: any) {
    super(opts);
  }

  log(info: any, callback: () => void) {
    setImmediate(() => {
      this.emit('logged', info);
    });

    if (info.level === 'error' && process.env.SENTRY_DSN) {
      const err = info.error || info.message;
      if (err instanceof Error) {
        Sentry.captureException(err, { extra: info });
      } else {
        Sentry.captureMessage(String(err), { level: 'error', extra: info });
      }
    }

    callback();
  }
}

export const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: logFormat,
  defaultMeta: { service: 'serenut-api' },
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(({ timestamp, level, message, ...meta }) => {
          return `[${timestamp}] ${level}: ${message} ${Object.keys(meta).length ? JSON.stringify(meta) : ''}`;
        })
      )
    }),
    new winston.transports.File({ 
      filename: path.join(process.cwd(), 'logs/error.log'), 
      level: 'error' 
    }),
    new winston.transports.File({ 
      filename: path.join(process.cwd(), 'logs/combined.log') 
    }),
    new SentryTransport({ level: 'error' })
  ],
  exceptionHandlers: [
    new winston.transports.File({
      filename: path.join(process.cwd(), 'logs/exceptions.log'),
    }),
  ],
  rejectionHandlers: [
    new winston.transports.File({
      filename: path.join(process.cwd(), 'logs/rejections.log'),
    }),
  ],
  // A rejected async request must be recorded and returned as an error; it
  // must not terminate the whole API process. Fatal native/process failures
  // remain visible to Docker's health/restart policy.
  exitOnError: false,
});
