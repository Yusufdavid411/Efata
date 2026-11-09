import { createServer } from 'node:http';
import health from '../api/health.mjs';
import live from '../api/live.mjs';

const port = Number(process.env.PORT ?? 3000);
createServer((req, res) => {
  if (req.url === '/api/health') return health(req, res);
  if (req.url === '/api/live') return live(req, res);
  res.statusCode = 404;
  res.end();
}).listen(port, '127.0.0.1', () => console.log('EFATA health check: http://127.0.0.1:' + port + '/api/health'));
