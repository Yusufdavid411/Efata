import { createServer } from 'node:http';
import health from '../api/health.mjs';
import live from '../api/live.mjs';
import orderHistory from '../api/order-history.mjs';

const port = Number(process.env.PORT ?? 3000);
createServer((req, res) => {
  const path = req.url.split('?', 1)[0];
  if (path === '/api/health') return health(req, res);
  if (path === '/api/live') return live(req, res);
  if (path === '/api/order-history') return orderHistory(req, res);
  res.statusCode = 404;
  res.end();
}).listen(port, '127.0.0.1', () => console.log('EFATA health check: http://127.0.0.1:' + port + '/api/health'));
