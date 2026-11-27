import type { NextConfig } from "next";

// Cabeçalhos de segurança, em todas as respostas:
// - X-Robots-Tag: nenhum buscador (Google incluído) lista páginas do sistema;
// - frame-ancestors/X-Frame-Options: o sistema não abre dentro de outro site
//   (barra "clickjacking");
// - nosniff, Referrer-Policy e HSTS: boas práticas básicas;
// - Permissions-Policy: o sistema não usa câmera, microfone nem localização.
const SECURITY_HEADERS = [
  { key: "X-Robots-Tag", value: "noindex, nofollow, noarchive, nosnippet, noimageindex" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Content-Security-Policy", value: "frame-ancestors 'none'" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), payment=()" },
];

const nextConfig: NextConfig = {
  // Não anuncia a tecnologia do servidor.
  poweredByHeader: false,
  async headers() {
    return [{ source: "/:path*", headers: SECURITY_HEADERS }];
  },
  // @motor/core é consumido como código-fonte TS (imports com extensão .ts),
  // então o Next transpila o pacote em vez de exigir build separado.
  transpilePackages: ["@motor/core"],
  // Supabase também fica fora do bundle do Next: dentro dele a biblioteca era
  // copiada uma vez por camada do servidor (três cópias, ~110 KiB a mais no
  // Worker, que tem limite de 3 MiB). Fora, o OpenNext a empacota uma vez só.
  serverExternalPackages: ["@supabase/supabase-js", "@supabase/ssr"],
};

export default nextConfig;

// Permite usar recursos do Cloudflare no `next dev` (hospedagem: Cloudflare Workers via OpenNext).
import { initOpenNextCloudflareForDev } from "@opennextjs/cloudflare";
if (process.env.NODE_ENV === "development") initOpenNextCloudflareForDev();
