import type { ReactNode } from "react";

interface FeatureCardProps {
  title: string;
  description: string;
  icon: ReactNode;
}

export default function FeatureCard({ title, description, icon }: FeatureCardProps) {
  return (
    <>
      <div className="feature-card">
        <div className="feature-icon">{icon}</div>
        <h3>{title}</h3>
        <p>{description}</p>
      </div>

      <style>{featureCardStyles}</style>
    </>
  );
}

const featureCardStyles = `
  .feature-card { padding: 32px; background: var(--bg-card); border: 1px solid var(--border); border-radius: 16px; transition: all 0.3s ease; }
  .feature-card:hover { background: var(--bg-card-hover); border-color: var(--border-hover); }
  .feature-icon { width: 48px; height: 48px; display: flex; align-items: center; justify-content: center; margin-bottom: 20px; color: var(--primary); }
  .feature-card h3 { font-size: 17px; font-weight: 600; margin-bottom: 8px; color: var(--text); letter-spacing: -0.01em; }
  .feature-card p { font-size: 15px; color: var(--text-secondary); line-height: 1.6; }
  @media (max-width: 768px) {
    .feature-card { padding: 24px; }
    .feature-card h3 { font-size: 16px; }
    .feature-card p { font-size: 14px; }
  }
`;
