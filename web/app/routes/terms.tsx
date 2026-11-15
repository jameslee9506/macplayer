import type { MetaFunction } from "react-router";
import { Link } from "react-router";

export const meta: MetaFunction = () => [
  { title: "Terms of Service - MacPlayer" },
  { name: "description", content: "MacPlayer terms of service. Free, open-source macOS video player." },
  { property: "og:title", content: "Terms of Service - MacPlayer" },
  { name: "robots", content: "index, follow" },
];

export default function Terms() {
  return (
    <>
      <div className="legal-page container">
        <h1>Terms of Service</h1>
        <p className="legal-updated">Last updated: February 2026</p>

        <div className="legal-content">
          <section>
            <h2>Acceptance of Terms</h2>
            <p>
              By downloading or using MacPlayer (&quot;the Software&quot;), you agree to these terms.
              If you do not agree, do not use the Software.
            </p>
          </section>

          <section>
            <h2>License</h2>
            <p>
              MacPlayer is open-source software. The source code is available on GitHub
              and subject to its respective open-source license. You are free to use, modify,
              and distribute the Software in accordance with the license terms.
            </p>
          </section>

          <section>
            <h2>Use of the Software</h2>
            <p>MacPlayer is provided for personal and commercial use. You may:</p>
            <ul>
              <li>Use the Software on any number of devices you own</li>
              <li>Modify the Software for your own use</li>
              <li>Distribute the Software in accordance with the open-source license</li>
            </ul>
          </section>

          <section>
            <h2>Disclaimer of Warranties</h2>
            <p>
              The Software is provided &quot;as is&quot; without warranty of any kind, express or implied,
              including but not limited to the warranties of merchantability, fitness for a particular
              purpose, and noninfringement.
            </p>
          </section>

          <section>
            <h2>Limitation of Liability</h2>
            <p>
              In no event shall the authors or copyright holders be liable for any claim, damages,
              or other liability, whether in an action of contract, tort, or otherwise, arising from,
              out of, or in connection with the Software or the use or other dealings in the Software.
            </p>
          </section>

          <section>
            <h2>Content Responsibility</h2>
            <p>
              MacPlayer is a media player. You are solely responsible for the content you play.
              The Software does not provide, host, or distribute any media content.
            </p>
          </section>

          <section>
            <h2>Changes to Terms</h2>
            <p>
              We reserve the right to update these terms at any time. Changes will be posted on this page.
              Continued use of the Software after changes constitutes acceptance of the new terms.
            </p>
          </section>

          <section>
            <h2>Contact</h2>
            <p>
              For questions about these terms, please open an issue on our{" "}
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
