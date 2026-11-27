import type { MetadataRoute } from "next";
import { APP_DESCRIPTION, APP_NAME, APP_SHORT_NAME } from "@/lib/brand";

/**
 * Manifesto do aplicativo (PWA): é o que permite "Instalar" / "Adicionar à
 * Tela de Início" no celular e abrir o sistema sem a barra do navegador.
 * Servido em /manifest.webmanifest (liberado sem login no middleware).
 */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: APP_NAME,
    short_name: APP_SHORT_NAME,
    description: APP_DESCRIPTION,
    lang: "pt-BR",
    id: "/",
    start_url: "/",
    scope: "/",
    display: "standalone",
    orientation: "portrait",
    background_color: "#ffffff",
    theme_color: "#092c23",
    icons: [
      { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icons/maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
    shortcuts: [
      { name: "Quadros", url: "/board" },
      { name: "Conversas", url: "/canais" },
      { name: "Avisos", url: "/avisos" },
    ],
  };
}
