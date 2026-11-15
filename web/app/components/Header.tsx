import { useState, useEffect, useCallback } from "react";
import { Link } from "react-router";

export default function Header() {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  const closeMenus = useCallback((e: MouseEvent) => {
    const target = e.target as HTMLElement;
    if (!target.closest(".mobile-menu") && !target.closest(".hamburger-btn"))
      setMobileMenuOpen(false);
  }, []);

  useEffect(() => {
    window.addEventListener("click", closeMenus);
    return () => window.removeEventListener("click", closeMenus);
  }, [closeMenus]);

  return (
    <>
      <header className="header">
        <div className="container">
          <div className="nav-content">
            <Link to="/" className="logo">
              <img src="/favicon.png" alt="MacPlayer" className="logo-icon" />
              <span className="logo-text">MacPlayer</span>
            </Link>

            <div className="nav-center desktop">
              <Link to="/blog" className="nav-link">Blog</Link>
              <Link to="/download" className="nav-link">Download</Link>
              <a href="https://github.com/jameslee9506/macplayer" target="_blank" rel="noopener noreferrer" className="nav-link">GitHub</a>
            </div>

            <div className="nav-right desktop">
              <Link to="/download" className="btn btn-primary btn-sm">
                Download now
              </Link>
            </div>

            <button
              className="hamburger-btn mobile"
              aria-label="Menu"
              onClick={(e) => {
                e.stopPropagation();
                setMobileMenuOpen(!mobileMenuOpen);
              }}
            >
              {mobileMenuOpen ? (
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <line x1="18" y1="6" x2="6" y2="18" />
                  <line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              ) : (
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <line x1="4" y1="7" x2="20" y2="7" />
                  <line x1="4" y1="17" x2="20" y2="17" />
                </svg>
              )}
            </button>
          </div>
        </div>

        {mobileMenuOpen && (
          <div className="mobile-menu">
            <Link to="/blog" className="mobile-link" onClick={() => setMobileMenuOpen(false)}>Blog</Link>
            <Link to="/download" className="mobile-link" onClick={() => setMobileMenuOpen(false)}>Download</Link>
            <a href="https://github.com/jameslee9506/macplayer" target="_blank" rel="noopener noreferrer" className="mobile-link" onClick={() => setMobileMenuOpen(false)}>GitHub</a>
            <div className="mobile-divider" />
            <Link to="/privacy" className="mobile-link secondary" onClick={() => setMobileMenuOpen(false)}>Privacy</Link>
            <Link to="/terms" className="mobile-link secondary" onClick={() => setMobileMenuOpen(false)}>Terms</Link>
          </div>
        )}
      </header>

      <style>{headerStyles}</style>
    </>
  );
}

const headerStyles = `
  .header { position: sticky; top: 0; z-index: 50; background: rgba(0, 0, 0, 0.6); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); border-bottom: 1px solid var(--border); }
  .nav-content { display: flex; justify-content: space-between; align-items: center; height: 64px; }
  .logo { display: flex; align-items: center; gap: 10px; text-decoration: none; }
  .logo-icon { width: 28px; height: 28px; border-radius: 6px; }
  .logo-text { font-size: 17px; font-weight: 600; color: var(--text); letter-spacing: -0.02em; }
  .nav-center { display: flex; align-items: center; gap: 32px; }
  .nav-link { font-size: 14px; color: var(--text-secondary); transition: color 0.2s; }
  .nav-link:hover { color: var(--text); }
  .nav-right { display: flex; align-items: center; }
  .btn-sm { padding: 8px 20px; font-size: 14px; border-radius: 8px; }
  .hamburger-btn { display: none; width: 40px; height: 40px; border: none; background: none; cursor: pointer; color: var(--text); padding: 8px; }
  .mobile-menu { display: none; position: fixed; top: 65px; left: 0; right: 0; bottom: 0; background: rgba(0, 0, 0, 0.95); backdrop-filter: blur(20px); padding: 32px; z-index: 100; }
  .mobile-link { display: block; padding: 16px 0; font-size: 18px; color: var(--text); text-decoration: none; }
  .mobile-link.secondary { font-size: 15px; color: var(--text-secondary); }
  .mobile-link:hover { color: var(--primary); }
  .mobile-divider { height: 1px; background: var(--border); margin: 12px 0; }
  .desktop { display: flex; }
  .mobile { display: none; }
  @media (max-width: 768px) {
    .nav-content { height: 56px; }
    .logo-icon { width: 24px; height: 24px; }
    .logo-text { font-size: 16px; }
    .desktop { display: none !important; }
    .mobile { display: flex; }
    .hamburger-btn { display: flex; align-items: center; justify-content: center; }
    .mobile-menu { display: block; }
  }
`;
