import type { MetaFunction } from "react-router";
import { Link } from "react-router";
import FeatureCard from "~/components/FeatureCard";
import FAQ from "~/components/FAQ";
import DotWave from "~/components/DotWave";

export const meta: MetaFunction = () => [
  { title: "MacPlayer - The fastest free video player for Mac" },
  { name: "description", content: "The fastest, most powerful free video player for Mac. Powered by mpv with a native SwiftUI interface. MKV, WebM, AVI, HDR, filters, bookmarks." },
  { property: "og:type", content: "website" },
  { property: "og:site_name", content: "MacPlayer" },
  { property: "og:title", content: "MacPlayer - The fastest free video player for Mac" },
  { property: "og:description", content: "The fastest, most powerful free video player for Mac. Powered by mpv with a native SwiftUI interface. MKV, WebM, AVI, HDR, filters, bookmarks." },
  { property: "og:locale", content: "en_US" },
  { property: "og:image", content: "https://raw.githubusercontent.com/jameslee9506/macplayer/main/web/public/og-image.png" },
  { name: "twitter:card", content: "summary_large_image" },
  { name: "twitter:title", content: "MacPlayer - The fastest free video player for Mac" },
  { name: "twitter:description", content: "The fastest, most powerful free video player for Mac. Powered by mpv with a native SwiftUI interface. MKV, WebM, AVI, HDR, filters, bookmarks." },
  { name: "twitter:image", content: "https://raw.githubusercontent.com/jameslee9506/macplayer/main/web/public/og-image.png" },
  { name: "robots", content: "index, follow" },
  { name: "author", content: "MacPlayer" },
  { name: "keywords", content: "video player, macOS, mpv, libmpv, MKV, WebM, HDR, native, Mac, media player, SwiftUI" },
];

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": "#website",
      name: "MacPlayer",
      description: "The fastest, most powerful free video player for Mac",
    },
    {
      "@type": "SoftwareApplication",
      "@id": "#software",
      name: "MacPlayer",
      description: "The fastest, most powerful free video player for Mac. Powered by mpv with a native SwiftUI interface. MKV, WebM, AVI, HDR, filters, bookmarks.",
      applicationCategory: "MultimediaApplication",
      operatingSystem: "macOS 15.0+",
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
      downloadUrl: "https://github.com/jameslee9506/macplayer/releases",
      softwareVersion: "1.0.1",
      featureList: [
        "mpv-powered playback engine",
        "MKV, WebM, AVI, MP4 and all major formats",
        "HDR support with mpv native tone mapping",
        "mpv native subtitle rendering (SRT, ASS, VTT)",
        "Instant seek preview with pre-generated thumbnails",
        "Bookmarks with thumbnails and A-B loop",
        "Customizable keyboard shortcuts",
        "Picture-in-Picture",
        "Native SwiftUI interface",
      ],
    },
    {
      "@type": "FAQPage",
      "@id": "#faq",
      mainEntity: [
        { "@type": "Question", name: "Is MacPlayer free?", acceptedAnswer: { "@type": "Answer", text: "Yes, MacPlayer is completely free and open-source." } },
        { "@type": "Question", name: "What macOS version is required?", acceptedAnswer: { "@type": "Answer", text: "MacPlayer requires macOS 15.0 (Sequoia) or later." } },
        { "@type": "Question", name: "Does MacPlayer collect any data?", acceptedAnswer: { "@type": "Answer", text: "No. MacPlayer is 100% offline. All data is stored locally on your Mac." } },
      ],
    },
  ],
};

export default function Index() {
  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      {/* Hero */}
      <section className="hero">
        <DotWave />
        <div className="container">
          <div className="hero-inner">
            <span className="hero-badge">Free &amp; Open Source</span>
            <h1>
              <span className="hero-gradient">The fastest</span>
              <br />
              video player
              <br />
              <span className="hero-dim">for Mac.</span>
            </h1>
            <p className="hero-desc">
              Powered by mpv. Native SwiftUI interface.
              <br />
              MKV, WebM, HDR, filters, bookmarks &mdash; all built in.
            </p>
            <div className="hero-actions">
              <Link to="/download" className="btn btn-primary btn-lg">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
                </svg>
                Download for macOS
              </Link>
              <span className="hero-note">macOS 15.0+ &middot; No sign-up required</span>
            </div>
          </div>
        </div>
        <div className="hero-glow" />
      </section>

      {/* Pillars */}
      <section className="pillars">
        <div className="container">
          <div className="pillars-grid">
            <div className="pillar">
              <span className="pillar-label">mpv Engine</span>
              <p>Powered by libmpv — the same engine behind IINA. Plays everything: MKV, WebM, AVI, MP4, and more.</p>
            </div>
            <div className="pillar">
              <span className="pillar-label">Native UI</span>
              <p>Pure SwiftUI interface designed for macOS. Feels right at home on your Mac.</p>
            </div>
            <div className="pillar">
              <span className="pillar-label">Privacy First</span>
              <p>100% offline. No telemetry, no network requests. All data stays on your Mac.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Why Section */}
      <section className="why">
        <div className="container">
          <div className="why-header">
            <h2>Beyond basic playback</h2>
            <p>Everything you need in a video player, nothing you don&apos;t.</p>
          </div>
          <div className="features-grid">
            <FeatureCard
              title="HDR Support"
              description="PQ and HLG tone mapping with automatic detection. Experience content the way it was meant to be seen."
              icon={
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <circle cx="12" cy="12" r="5" />
                  <line x1="12" y1="1" x2="12" y2="3" />
                  <line x1="12" y1="21" x2="12" y2="23" />
                  <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
                  <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
                  <line x1="1" y1="12" x2="3" y2="12" />
                  <line x1="21" y1="12" x2="23" y2="12" />
                  <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
                  <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
                </svg>
              }
            />
            <FeatureCard
              title="Universal Formats"
              description="Play MKV, WebM, AVI, MP4, FLAC, and virtually any format. Powered by mpv with hardware-accelerated decoding."
              icon={
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <polygon points="12 2 2 7 12 12 22 7 12 2" />
                  <polyline points="2 17 12 22 22 17" />
                  <polyline points="2 12 12 17 22 12" />
                </svg>
              }
            />
            <FeatureCard
              title="Video Filters"
              description="Real-time brightness, contrast, saturation, sharpen, and deband filters. Processed via mpv for zero-overhead adjustments."
              icon={
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <circle cx="13.5" cy="6.5" r="4.5" />
                  <circle cx="17.5" cy="17.5" r="4.5" />
                  <circle cx="6.5" cy="17.5" r="4.5" />
                </svg>
              }
            />
            <FeatureCard
              title="Smart Subtitles"
              description="SRT, ASS, and VTT subtitle formats with mpv's built-in rendering. Automatic file matching and styled ASS support."
              icon={
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <rect x="2" y="3" width="20" height="14" rx="2" />
                  <line x1="8" y1="21" x2="16" y2="21" />
                  <line x1="12" y1="17" x2="12" y2="21" />
                  <path d="M6 10h4M14 10h4" />
                </svg>
              }
            />
            <FeatureCard
              title="Bookmarks & A-B Loop"
              description="Save timestamp bookmarks with thumbnails. Set A-B loop points for repeated playback of any section."
              icon={
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <path d="M19 21l-7-5-7 5V5a2 2 0 012-2h10a2 2 0 012 2z" />
                </svg>
              }
            />
            <FeatureCard
              title="Instant Seek Preview"
              description="Pre-generated thumbnails across the entire timeline. Hover the seek bar for instant, flicker-free preview at any position — no loading delay."
              icon={
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <rect x="2" y="3" width="20" height="14" rx="2" />
                  <polygon points="10 7 15 10 10 13 10 7" fill="currentColor" stroke="none" />
                  <line x1="2" y1="20" x2="22" y2="20" />
                  <circle cx="14" cy="20" r="1.5" fill="currentColor" stroke="none" />
                </svg>
              }
            />
          </div>
        </div>
      </section>

      {/* Compare */}
      <section className="compare">
        <div className="container">
          <div className="compare-header-section">
            <h2>How it compares</h2>
          </div>
          <div className="compare-table">
            <div className="compare-thead">
              <div className="compare-cell th-label" />
              <div className="compare-cell th">QuickTime</div>
              <div className="compare-cell th">VLC</div>
              <div className="compare-cell th">IINA</div>
              <div className="compare-cell th th-highlight">MacPlayer</div>
            </div>
            {([
              ["MKV / WebM / AVI", false, true, true, true],
              ["HDR Support", "Partial", "Partial", true, true],
              ["Instant Seek Preview", "Partial", false, true, true],
              ["Built-in Bookmarks", false, "Partial", false, true],
              ["Picture-in-Picture", true, false, true, true],
              ["Snappy, Intuitive UI", "Limited", false, true, true],
              ["100% Offline", true, false, false, true],
            ] as const).map(([label, qt, vlc, iina, hp]) => (
              <div className="compare-tr" key={label}>
                <div className="compare-cell td-label">{label}</div>
                {[qt, vlc, iina, hp].map((val, j) => (
                  <div className={`compare-cell td${j === 3 ? " td-highlight" : ""}`} key={j}>
                    {val === true ? (
                      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={j === 3 ? "#ff6b35" : "rgba(255,255,255,0.3)"} strokeWidth="2">
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                    ) : val === false ? (
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.12)" strokeWidth="2">
                        <line x1="18" y1="6" x2="6" y2="18" />
                        <line x1="6" y1="6" x2="18" y2="18" />
                      </svg>
                    ) : (
                      <span className="compare-partial">{String(val)}</span>
                    )}
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Tech */}
      <section className="tech">
        <div className="container">
          <h2 className="tech-title">Built with</h2>
          <div className="tech-grid">
            {[
              { name: "libmpv", desc: "Media decoding & rendering engine" },
              { name: "SwiftUI", desc: "Modern native macOS UI" },
              { name: "OpenGL", desc: "mpv render API integration" },
              { name: "SQLite", desc: "Bookmarks, history & settings" },
              { name: "VideoToolbox", desc: "Hardware-accelerated decoding" },
              { name: "Swift Concurrency", desc: "Strict concurrency" },
            ].map((item) => (
              <div className="tech-item" key={item.name}>
                <span className="tech-name">{item.name}</span>
                <span className="tech-desc">{item.desc}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section className="faq-section">
        <div className="container">
          <FAQ />
        </div>
      </section>

      <style>{indexStyles}</style>
    </>
  );
}

const indexStyles = `
  /* Hero */
  .hero { position: relative; overflow: hidden; padding: 120px 0 140px; }
  .hero-inner { text-align: center; position: relative; z-index: 1; }
  .hero h1 { font-size: 80px; font-weight: 700; line-height: 1.0; letter-spacing: -0.04em; margin-bottom: 28px; }
  .hero-badge { display: inline-block; font-size: 14px; font-weight: 500; color: var(--primary); border: 1px solid rgba(255, 107, 53, 0.25); padding: 6px 18px; border-radius: 100px; margin-bottom: 24px; letter-spacing: 0.02em; background: rgba(255, 107, 53, 0.06); }
  .hero-gradient { background: linear-gradient(135deg, #ff6b35, #ff9a6c); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .hero-dim { color: rgba(255, 255, 255, 0.35); -webkit-text-fill-color: rgba(255, 255, 255, 0.35); }
  .hero-desc { font-size: 19px; color: var(--text-secondary); line-height: 1.7; margin-bottom: 48px; max-width: 480px; margin-left: auto; margin-right: auto; }
  .hero-actions { display: flex; flex-direction: column; align-items: center; gap: 16px; }
  .hero-note { font-size: 14px; color: var(--text-muted); }
  .btn-lg { padding: 16px 36px; font-size: 16px; border-radius: 12px; font-weight: 600; }
  .hero-glow { position: absolute; bottom: -200px; left: 50%; transform: translateX(-50%); width: 600px; height: 400px; background: radial-gradient(ellipse, rgba(255, 107, 53, 0.08) 0%, transparent 70%); pointer-events: none; }

  /* Pillars */
  .pillars { padding: 80px 0; border-top: 1px solid var(--border); }
  .pillars-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1px; background: var(--border); border-radius: 16px; overflow: hidden; }
  .pillar { background: var(--bg); padding: 40px 32px; }
  .pillar-label { display: inline-block; font-size: 13px; font-weight: 600; color: var(--primary); text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 12px; }
  .pillar p { font-size: 15px; color: var(--text-secondary); line-height: 1.6; }

  /* Why / Features */
  .why { padding: 100px 0; }
  .why-header { margin-bottom: 64px; }
  .why-header h2 { font-size: 40px; font-weight: 700; letter-spacing: -0.03em; margin-bottom: 12px; }
  .why-header p { font-size: 17px; color: var(--text-secondary); }
  .features-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }

  /* Compare */
  .compare { padding: 100px 0; }
  .compare-header-section { margin-bottom: 48px; }
  .compare-header-section h2 { font-size: 32px; font-weight: 700; letter-spacing: -0.03em; }
  .compare-table { border: 1px solid var(--border); border-radius: 16px; overflow: hidden; }
  .compare-thead, .compare-tr { display: grid; grid-template-columns: 1.6fr repeat(4, 1fr); }
  .compare-thead { border-bottom: 1px solid var(--border); }
  .compare-cell { padding: 18px 20px; display: flex; align-items: center; justify-content: center; }
  .compare-cell.th-label { justify-content: flex-start; }
  .compare-cell.th { font-size: 14px; font-weight: 500; color: var(--text-muted); }
  .compare-cell.th-highlight { color: var(--primary); font-weight: 600; }
  .compare-tr { border-bottom: 1px solid var(--border); }
  .compare-tr:last-child { border-bottom: none; }
  .compare-cell.td-label { justify-content: flex-start; font-size: 15px; font-weight: 500; color: var(--text-secondary); }
  .compare-cell.td { font-size: 15px; }
  .compare-cell.td-highlight { background: rgba(255, 107, 53, 0.04); }
  .compare-partial { font-size: 13px; color: var(--text-muted); }

  /* Tech */
  .tech { padding: 80px 0; border-top: 1px solid var(--border); }
  .tech-title { font-size: 32px; font-weight: 700; letter-spacing: -0.03em; margin-bottom: 40px; }
  .tech-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
  .tech-item { padding: 24px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 12px; transition: border-color 0.2s; }
  .tech-item:hover { border-color: var(--border-hover); }
  .tech-name { display: block; font-size: 15px; font-weight: 600; color: var(--text); margin-bottom: 4px; }
  .tech-desc { font-size: 13px; color: var(--text-muted); }

  /* FAQ section */
  .faq-section { border-top: 1px solid var(--border); }

  @media (max-width: 768px) {
    .hero { padding: 80px 0 100px; }
    .hero h1 { font-size: 44px; }
    .hero-desc { font-size: 16px; }
    .btn-lg { padding: 14px 28px; font-size: 15px; }
    .hero-glow { width: 300px; height: 200px; }
    .pillars-grid { grid-template-columns: 1fr; }
    .pillar { padding: 28px 24px; }
    .why { padding: 64px 0; }
    .why-header { margin-bottom: 40px; }
    .why-header h2 { font-size: 28px; }
    .why-header p { font-size: 15px; }
    .features-grid { grid-template-columns: 1fr; gap: 12px; }
    .compare { padding: 64px 0; }
    .compare-header-section h2 { font-size: 24px; }
    .compare-thead, .compare-tr { grid-template-columns: 1.3fr repeat(4, 1fr); }
    .compare-cell { padding: 14px 8px; }
    .compare-cell.th { font-size: 11px; }
    .compare-cell.td-label { font-size: 13px; }
    .tech { padding: 64px 0; }
    .tech-title { font-size: 24px; }
    .tech-grid { grid-template-columns: 1fr 1fr; }
  }
  @media (max-width: 480px) {
    .hero h1 { font-size: 36px; }
    .pillars-grid { border-radius: 12px; }
    .compare-table { border-radius: 12px; }
    .compare-thead, .compare-tr { grid-template-columns: 1.1fr repeat(4, 1fr); }
    .compare-cell { padding: 12px 6px; }
    .compare-cell.th { font-size: 10px; }
    .compare-cell.td-label { font-size: 12px; }
    .tech-grid { grid-template-columns: 1fr; }
  }
`;
