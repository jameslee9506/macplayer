import type { MetaFunction } from "react-router";
import { Link } from "react-router";

export const meta: MetaFunction = () => [
  { title: "Download - MacPlayer" },
  { name: "description", content: "Download MacPlayer for macOS. Free, open-source, native video player powered by mpv with HDR support." },
  { property: "og:title", content: "Download MacPlayer" },
  { property: "og:description", content: "Download MacPlayer for macOS. Free, open-source, native video player." },
  { name: "robots", content: "index, follow" },
];

export default function Download() {
  return (
    <>
      <div className="dl-page container">
        <section className="dl-hero">
          <h1>Download MacPlayer</h1>
          <p className="dl-desc">
            Free, open-source video player for macOS.
          </p>
        </section>

        <section className="dl-card-wrapper">
          <div className="dl-card">
            <div className="dl-card-top">
              <img src="/favicon.png" alt="MacPlayer" width="64" height="64" className="dl-icon" />
              <div>
                <h2>MacPlayer for macOS</h2>
                <div className="dl-meta">
                  <span className="dl-version">Source available</span>
                  <span className="dl-dot">&middot;</span>
                  <span className="dl-req">macOS 15.0+</span>
                </div>
              </div>
            </div>
            <a
              href="https://github.com/jameslee9506/macplayer/releases"
              className="btn btn-primary btn-lg dl-btn"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4" />
                <polyline points="7 10 12 15 17 10" />
                <line x1="12" y1="15" x2="12" y2="3" />
              </svg>
              View releases
            </a>
          </div>
        </section>

        <section className="dl-steps">
          <h2>Build from source</h2>
          <p>
            A MacPlayer binary has not been published yet. Follow the{" "}
            <a href="https://github.com/jameslee9506/macplayer#build-the-macos-app">build instructions on GitHub</a>.
          </p>
          <div className="steps-grid">
            {[
              { num: "1", title: "Clone", desc: "Get the MacPlayer source from GitHub." },
              { num: "2", title: "Prepare", desc: "Install dependencies and run the bundling script." },
              { num: "3", title: "Generate", desc: "Generate the Xcode project with XcodeGen." },
              { num: "4", title: "Run", desc: "Open MacPlayer.xcodeproj in Xcode and run the MacPlayer scheme." },
            ].map((step) => (
              <div className="step-item" key={step.num}>
                <span className="step-num">{step.num}</span>
                <h3>{step.title}</h3>
                <p>{step.desc}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="dl-trust">
          <div className="trust-grid">
            <div className="trust-item">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              </svg>
              <div>
                <h4>Privacy First</h4>
                <p>100% offline. No data collection.</p>
              </div>
            </div>
            <div className="trust-item">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <polyline points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
              </svg>
              <div>
                <h4>Native Performance</h4>
                <p>mpv engine + OpenGL rendering.</p>
              </div>
            </div>
            <div className="trust-item">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="3" y="3" width="18" height="18" rx="2" />
                <path d="M3 9h18M9 21V9" />
              </svg>
              <div>
                <h4>Lightweight</h4>
                <p>Single .app bundle, no setup.</p>
              </div>
            </div>
          </div>
        </section>

        <div className="dl-back">
          <Link to="/" className="btn btn-ghost">&larr; Back to home</Link>
        </div>
      </div>

      <style>{downloadStyles}</style>
    </>
  );
}

const downloadStyles = `
  .dl-page { padding-bottom: 80px; }
  .dl-hero { padding: 80px 0 48px; }
  .dl-hero h1 { font-size: 48px; font-weight: 700; letter-spacing: -0.04em; margin-bottom: 12px; }
  .dl-desc { font-size: 18px; color: var(--text-secondary); }

  .dl-card-wrapper { padding-bottom: 80px; }
  .dl-card { display: flex; flex-direction: column; gap: 32px; padding: 40px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 20px; max-width: 520px; }
  .dl-card-top { display: flex; gap: 20px; align-items: center; }
  .dl-icon { border-radius: 14px; }
  .dl-card-top h2 { font-size: 20px; font-weight: 600; margin-bottom: 6px; }
  .dl-meta { display: flex; align-items: center; gap: 8px; }
  .dl-version { font-size: 14px; color: var(--primary); font-weight: 500; }
  .dl-dot { color: var(--text-muted); }
  .dl-req { font-size: 13px; color: var(--text-muted); }
  .dl-btn { width: 100%; }
  .btn-lg { padding: 16px 36px; font-size: 16px; border-radius: 12px; font-weight: 600; }

  .dl-steps { padding: 64px 0; border-top: 1px solid var(--border); }
  .dl-steps h2 { font-size: 24px; font-weight: 700; letter-spacing: -0.02em; margin-bottom: 36px; }
  .steps-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; }
  .step-item { padding: 28px 24px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 14px; }
  .step-num { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; background: var(--primary); color: white; border-radius: 8px; font-size: 13px; font-weight: 600; margin-bottom: 16px; }
  .step-item h3 { font-size: 16px; font-weight: 600; margin-bottom: 6px; }
  .step-item p { font-size: 14px; color: var(--text-secondary); line-height: 1.5; }

  .dl-trust { padding: 64px 0; border-top: 1px solid var(--border); }
  .trust-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
  .trust-item { display: flex; gap: 14px; padding: 24px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 14px; }
  .trust-item svg { color: var(--primary); flex-shrink: 0; margin-top: 2px; }
  .trust-item h4 { font-size: 15px; font-weight: 600; margin-bottom: 4px; }
  .trust-item p { font-size: 13px; color: var(--text-secondary); }

  .dl-back { padding-top: 32px; }

  @media (max-width: 768px) {
    .dl-hero h1 { font-size: 32px; }
    .dl-desc { font-size: 16px; }
    .dl-card { padding: 28px; max-width: 100%; }
    .steps-grid { grid-template-columns: 1fr 1fr; }
    .trust-grid { grid-template-columns: 1fr; }
  }
  @media (max-width: 480px) {
    .steps-grid { grid-template-columns: 1fr; }
  }
`;
