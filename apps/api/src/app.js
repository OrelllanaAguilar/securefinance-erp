import fs from 'node:fs';
import path from 'node:path';
import compression from 'compression';
import cookieParser from 'cookie-parser';
import express from 'express';
import helmet from 'helmet';
import { createApiRouter } from './routes/index.js';
import { errorHandler, notFoundHandler } from './middleware/errors.js';
import { sameOrigin } from './middleware/origin.js';
import { requestContext } from './middleware/request-context.js';

export function createApp({ config, database }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);
  app.locals.config = config;
  app.locals.database = database;

  app.use(requestContext);
  app.use((request, response, next) => {
    const started = performance.now();
    response.on('finish', () => {
      console.info('Solicitud completada.', {
        correlationId: request.correlationId,
        method: request.method,
        path: request.path,
        status: response.statusCode,
        durationMs: Math.round(performance.now() - started),
      });
    });
    next();
  });
  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          baseUri: ["'self'"],
          connectSrc: ["'self'"],
          fontSrc: ["'self'"],
          formAction: ["'self'"],
          frameAncestors: ["'none'"],
          imgSrc: ["'self'", 'data:'],
          objectSrc: ["'none'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'"],
        },
      },
      crossOriginEmbedderPolicy: false,
    }),
  );
  app.use(compression());
  app.use(cookieParser());
  app.use(express.json({ limit: '256kb', strict: true }));
  app.use(sameOrigin);
  app.use('/api', (_request, response, next) => {
    response.set('Cache-Control', 'no-store');
    response.set('Pragma', 'no-cache');
    next();
  });
  app.use('/api', createApiRouter());

  const indexPath = path.join(config.webDistPath, 'index.html');
  if (fs.existsSync(indexPath)) {
    app.use(
      express.static(config.webDistPath, {
        index: false,
        immutable: true,
        maxAge: '1y',
        setHeaders(response, filePath) {
          if (filePath.endsWith('index.html') || filePath.endsWith('theme-init.js')) {
            response.setHeader('Cache-Control', 'no-store');
          }
        },
      }),
    );
    app.get('/{*splat}', (_request, response) => {
      response.set('Cache-Control', 'no-store');
      response.sendFile(indexPath);
    });
  } else {
    app.use(notFoundHandler);
  }

  app.use(errorHandler);
  return app;
}
