/** @type {import('next').NextConfig} */

// GitHub Pages serves a project site under /<repo>. Set BASE_PATH=/inLAY in CI
// so asset + route URLs resolve; locally it's unset, so dev/preview run at root.
const basePath = process.env.BASE_PATH || "";

const nextConfig = {
  // Fully static output so it hosts anywhere (GitHub Pages, Netlify, a bucket).
  output: "export",
  images: { unoptimized: true },
  trailingSlash: true,
  basePath: basePath || undefined,
  assetPrefix: basePath || undefined,
  // Expose the prefix to client components that build asset URLs by hand.
  env: { NEXT_PUBLIC_BASE_PATH: basePath },
};

export default nextConfig;
