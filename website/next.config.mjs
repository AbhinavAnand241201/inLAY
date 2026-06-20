/** @type {import('next').NextConfig} */
const nextConfig = {
  // Fully static output so it hosts anywhere (GitHub Pages, Netlify, a bucket).
  output: "export",
  images: { unoptimized: true },
  trailingSlash: true,
};

export default nextConfig;
