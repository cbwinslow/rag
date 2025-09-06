/** @type {import('next').NextConfig} */
const path = require('path');

const nextConfig = {
  output: "export",
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  experimental: {
    esmExternals: "loose",
    outputFileTracingRoot: path.join(__dirname, "../"),
  },
};

module.exports = nextConfig;