import { Link } from "react-router";

export default function Footer() {
  return (
    <>
      <footer className="footer">
        <div className="container">
          <div className="footer-cta">
            <h2>The fastest free player for Mac.</h2>
            <p>Open-source. Zero dependencies. Pure speed.</p>
            <Link to="/download" className="btn btn-primary">
              Download now
            </Link>
          </div>

          <div className="footer-grid">
            <div className="footer-brand">
              <div className="footer-logo">
                <img src="/favicon.png" alt="MacPlayer" className="footer-logo-icon" />
                <span>MacPlayer</span>
              </div>
              <p className="footer-desc">Native macOS video player<br />powered by mpv &amp; SwiftUI.</p>
            </div>

            <div className="footer-col">
              <h4>Product</h4>
              <Link to="/download">Download</Link>
              <a href="https://github.com/jameslee9506/macplayer" target="_blank" rel="noopener noreferrer">GitHub</a>
            </div>

            <div className="footer-col">
              <h4>Legal</h4>
              <Link to="/privacy">Privacy Policy</Link>
              <Link to="/terms">Terms of Service</Link>
            </div>
          </div>

          <div className="footer-bottom">
            <p>&copy; {new Date().getFullYear()} MacPlayer. All rights reserved.</p>
          </div>
        </div>
      </footer>

      <style>{footerStyles}</style>
    </>
  );
}

const footerStyles = `
  .footer { border-top: 1px solid var(--border); padding-top: 0; }
  .footer-cta { text-align: center; padding: 100px 0 80px; }
  .footer-cta h2 { font-size: 40px; font-weight: 700; letter-spacing: -0.03em; margin-bottom: 12px; }
  .footer-cta p { font-size: 16px; color: var(--text-secondary); margin-bottom: 32px; }
  .footer-grid { display: flex; justify-content: space-between; gap: 48px; padding: 48px 0; border-top: 1px solid var(--border); }
  .footer-brand { max-width: 260px; }
  .footer-logo { display: flex; align-items: center; gap: 8px; font-size: 16px; font-weight: 600; margin-bottom: 12px; }
  .footer-logo-icon { width: 22px; height: 22px; border-radius: 5px; }
  .footer-desc { font-size: 14px; color: var(--text-muted); line-height: 1.6; }
  .footer-col { display: flex; flex-direction: column; gap: 12px; }
  .footer-col h4 { font-size: 13px; font-weight: 500; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 4px; }
  .footer-col a { font-size: 14px; color: var(--text-secondary); transition: color 0.2s; }
  .footer-col a:hover { color: var(--text); }
  .footer-bottom { padding: 24px 0; border-top: 1px solid var(--border); }
  .footer-bottom p { font-size: 13px; color: var(--text-muted); }
  @media (max-width: 768px) {
    .footer-cta { padding: 64px 0 56px; }
    .footer-cta h2 { font-size: 28px; }
    .footer-grid { flex-direction: column; gap: 36px; }
    .footer-brand { max-width: 100%; }
    .footer-bottom { text-align: center; }
  }
`;
