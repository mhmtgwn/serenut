import winston from 'winston';
import path from 'path';
import * as Sentry from '@sentry/node';

const logFormat = winston.format.combine(
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
      filename: path.join(__dirname, '../../../logs/error.log'), 
      level: 'error' 
    }),
    new winston.transports.File({ 
      filename: path.join(__dirname, '../../../logs/combined.log') 
    }),
    new SentryTransport({ level: 'error' })
  ]
});
