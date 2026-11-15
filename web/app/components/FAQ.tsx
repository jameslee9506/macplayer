interface FAQProps {
  showTitle?: boolean;
}

export default function FAQ({ showTitle = true }: FAQProps) {
  return (
    <>
      <section className={`faq${showTitle ? "" : " no-border"}`}>
        {showTitle && <h2 className="faq-title">Frequently asked questions</h2>}
        <div className="faq-list">
          <details className="faq-item">
            <summary>Is MacPlayer free?</summary>
            <p>
              Yes, MacPlayer is completely free and open-source. No ads, no subscriptions, no in-app purchases.
            </p>
          </details>
          <details className="faq-item">
            <summary>What formats does it support?</summary>
            <p>
              Powered by mpv/libmpv, MacPlayer plays virtually every format — MKV, WebM, AVI, MP4, FLAC, and more. Hardware-accelerated via VideoToolbox.
            </p>
          </details>
          <details className="faq-item">
            <summary>Does it collect any data?</summary>
            <p>
              No. MacPlayer is 100% offline. All data (bookmarks, playback history, settings) is stored locally on your Mac. Nothing is ever sent to the internet.
            </p>
          </details>
          <details className="faq-item">
            <summary>What macOS version is required?</summary>
            <p>
              MacPlayer requires macOS 15.0 (Sequoia) or later. It is built natively with Swift and SwiftUI for optimal performance on modern Macs.
            </p>
          </details>
          <details className="faq-item">
            <summary>How is it different from VLC or IINA?</summary>
            <p>
              MacPlayer combines mpv&apos;s powerful playback engine with a pure SwiftUI interface. Unlike VLC, it feels native to macOS. Unlike IINA, it offers bookmark management, a keyboard shortcut guide, and a modern SwiftUI-based UI with features like instant seek preview and per-file settings.
            </p>
          </details>
        </div>
      </section>

      <style>{faqStyles}</style>
    </>
  );
}

const faqStyles = `
  .faq { padding: 100px 0; }
  .faq.no-border { padding-top: 64px; }
  .faq-title { font-size: 32px; font-weight: 700; letter-spacing: -0.03em; margin-bottom: 48px; }
  .faq-list { max-width: 720px; }
  .faq-item { border-bottom: 1px solid var(--border); }
  .faq-item summary { padding: 24px 0; font-size: 16px; font-weight: 500; cursor: pointer; list-style: none; display: flex; justify-content: space-between; align-items: center; user-select: none; -webkit-user-select: none; color: var(--text); transition: color 0.2s; }
  .faq-item summary:hover { color: var(--text-secondary); }
  .faq-item summary::-webkit-details-marker { display: none; }
  .faq-item summary::after { content: "+"; font-size: 22px; font-weight: 300; color: var(--text-muted); transition: transform 0.2s; }
  .faq-item[open] summary::after { content: "\\2212"; }
  .faq-item p { padding-bottom: 24px; font-size: 15px; color: var(--text-secondary); line-height: 1.7; }
  @media (max-width: 768px) {
    .faq { padding: 64px 0; }
    .faq-title { font-size: 24px; margin-bottom: 32px; }
    .faq-item summary { padding: 20px 0; font-size: 15px; }
    .faq-item p { font-size: 14px; padding-bottom: 20px; }
  }
`;
