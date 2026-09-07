// Vercel supplies the request IP's country; do not return or persist the IP.
module.exports = function region(request, response) {
  response.setHeader('Cache-Control', 'private, no-store');
  response.setHeader('Vercel-CDN-Cache-Control', 'no-store');
  if (request.method !== 'GET') {
    response.setHeader('Allow', 'GET');
    return response.status(405).json({ error: 'Method not allowed' });
  }

  const country = request.headers['x-vercel-ip-country'];
  const countryCode = typeof country === 'string' && /^[A-Z]{2}$/.test(country)
    ? country : null;
  return response.status(200).json({ countryCode });
};
