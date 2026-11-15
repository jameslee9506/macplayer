import type { MetaFunction } from "react-router";
import { Link } from "react-router";

export const meta: MetaFunction = () => [
  { title: "Privacy Policy - MacPlayer" },
  { name: "description", content: "MacPlayer privacy policy. We don't collect any data. Everything stays on your Mac." },
  { property: "og:title", content: "Privacy Policy - MacPlayer" },
  { name: "robots", content: "index, follow" },
];

export default function Privacy() {
  return (
    <>
      <div className="legal-page container">
        <h1>Privacy Policy</h1>
        <p className="legal-updated">Last updated: February 2026</p>

        <div className="legal-content">
          <section>
            <h2>Overview</h2>
            <p>
              MacPlayer is a native macOS video player that operates entirely offline.
              We are committed to protecting your privacy. This policy explains our approach to data handling.
            </p>
          </section>

          <section>
            <h2>Data Collection</h2>
            <p>
              <strong>We do not collect any data.</strong> MacPlayer does not:
            </p>
            <ul>
              <li>Track your usage or behavior</li>
              <li>Collect analytics or telemetry</li>
              <li>Send any data over the network</li>
              <li>Use cookies or tracking technologies</li>
              <li>Require an account or login</li>
            </ul>
          </section>

          <section>
            <h2>Local Data Storage</h2>
            <p>MacPlayer stores the following data locally on your Mac:</p>
            <ul>
              <li><strong>Playback history</strong> &mdash; recently played files and resume positions</li>
              <li><strong>Bookmarks</strong> &mdash; timestamp bookmarks with thumbnail previews</li>
              <li><strong>Settings</strong> &mdash; your preferences and key bindings</li>
              <li><strong>Filter presets</strong> &mdash; custom video filter configurations</li>
            </ul>
            <p>
              All data is stored in your local user directory (UserDefaults and Application Support).
              None of this data ever leaves your computer.
            </p>
          </section>

          <section>
            <h2>Network Usage</h2>
            <p>
              MacPlayer does not make any network requests. The application operates entirely offline.
              There are no update checks, no crash reporting, and no external API calls.
            </p>
          </section>

          <section>
            <h2>Third-Party Services</h2>
            <p>MacPlayer does not integrate with any third-party services, SDKs, or analytics platforms.</p>
          </section>

          <section>
            <h2>Open Source</h2>
            <p>
              MacPlayer is open-source software. You can review the complete source code to verify
              our privacy practices at any time.
            </p>
          </section>

          <section>
            <h2>Changes to This Policy</h2>
            <p>
              If we ever change our privacy practices, we will update this page accordingly.
              Given the offline nature of the app, significant changes are unlikely.
            </p>
          </section>

          <section>
            <h2>Contact</h2>
            <p>
              For questions about this privacy policy, please open an issue on our{" "}
              <a href="https://github.com/jameslee9506/macplayer" target="_blank" rel="noopener noreferrer">
                GitHub repository
              </a>.
            </p>
          </section>
        </div>

        <div className="legal-back">
          <Link to="/" className="btn btn-ghost">&larr; Back to home</Link>
        </div>
      </div>

      <style>{legalStyles}</style>
    </>
  );
}

const legalStyles = `
  .legal-page { padding: 80px 0; max-width: 680px; }
  .legal-page h1 { font-size: 40px; font-weight: 700; letter-spacing: -0.03em; margin-bottom: 8px; }
  .legal-updated { font-size: 14px; color: var(--text-muted); margin-bottom: 56px; }
  .legal-content section { margin-bottom: 40px; }
  .legal-content h2 { font-size: 18px; font-weight: 600; margin-bottom: 12px; color: var(--text); }
  .legal-content p { font-size: 15px; color: var(--text-secondary); line-height: 1.8; margin-bottom: 12px; }
  .legal-content strong { color: var(--text); }
  .legal-content ul { list-style: none; padding: 0; margin: 12px 0; }
  .legal-content li { font-size: 15px; color: var(--text-secondary); line-height: 1.8; padding: 2px 0 2px 20px; position: relative; }
  .legal-content li::before { content: ""; position: absolute; left: 0; top: 12px; width: 6px; height: 6px; border-radius: 50%; background: var(--primary); opacity: 0.6; }
  .legal-content a { color: var(--primary); text-decoration: underline; text-underline-offset: 3px; text-decoration-color: rgba(255, 107, 53, 0.3); }
  .legal-content a:hover { text-decoration-color: var(--primary); }
  .legal-back { padding-top: 48px; border-top: 1px solid var(--border); margin-top: 16px; }
  @media (max-width: 768px) {
    .legal-page { padding: 48px 0; }
    .legal-page h1 { font-size: 28px; }
  }
`;
