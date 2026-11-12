/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",          // plain static files: host anywhere (GitHub Pages, Netlify, Vercel)
  images: { unoptimized: true },
  trailingSlash: true,
};
export default nextConfig;
