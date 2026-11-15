import type { MetaFunction } from "react-router";
import { Link } from "react-router";
import { blogPosts } from "~/data/blog-posts";

export const meta: MetaFunction = () => [
  { title: "Blog - MacPlayer" },
  { name: "description", content: "Technical articles about MacPlayer — the mpv-powered video player for macOS. Engineering deep dives, architecture decisions, and feature breakdowns." },
  { property: "og:title", content: "Blog - MacPlayer" },
  { property: "og:description", content: "Technical articles about MacPlayer — engineering deep dives, architecture decisions, and feature breakdowns." },
  { name: "robots", content: "index, follow" },
];

export default function BlogIndex() {
  return (
    <>
      <section className="blog-hero">
        <div className="container">
          <h1 className="blog-hero-title">Blog</h1>
          <p className="blog-hero-desc">Engineering deep dives, architecture decisions, and the story behind MacPlayer.</p>
        </div>
      </section>

      <section className="blog-list">
        <div className="container">
          <div className="blog-grid">
            {blogPosts.map((post) => (
              <Link to={`/blog/${post.slug}`} key={post.slug} className="blog-card">
                <div className="blog-card-tag">{post.tag}</div>
                <h2 className="blog-card-title">{post.title}</h2>
                <p className="blog-card-desc">{post.description}</p>
                <div className="blog-card-meta">
                  <span>{post.date}</span>
                  <span className="blog-card-dot" />
                  <span>{post.readTime} read</span>
                </div>
              </Link>
            ))}
          </div>
        </div>
      </section>

      <style>{blogIndexStyles}</style>
    </>
  );
}

const blogIndexStyles = `
  .blog-hero {
    padding: 80px 0 48px;
    text-align: center;
  }
  .blog-hero-title {
    font-size: 48px;
    font-weight: 700;
    letter-spacing: -0.03em;
    margin-bottom: 12px;
  }
  .blog-hero-desc {
    font-size: 18px;
    color: var(--text-secondary);
    max-width: 560px;
    margin: 0 auto;
    line-height: 1.6;
  }
  .blog-list {
    padding: 0 0 120px;
  }
  .blog-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 20px;
  }
  .blog-card {
    display: flex;
    flex-direction: column;
    padding: 32px;
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 16px;
    text-decoration: none;
    transition: all 0.25s ease;
  }
  .blog-card:hover {
    background: var(--bg-card-hover);
    border-color: var(--border-hover);
    transform: translateY(-2px);
  }
  .blog-card-tag {
    display: inline-block;
    width: fit-content;
    padding: 4px 12px;
    font-size: 12px;
    font-weight: 500;
    color: var(--primary);
    background: var(--primary-glow);
    border-radius: 20px;
    margin-bottom: 16px;
    letter-spacing: 0.02em;
  }
  .blog-card-title {
    font-size: 22px;
    font-weight: 600;
    color: var(--text);
    letter-spacing: -0.02em;
    line-height: 1.3;
    margin-bottom: 10px;
  }
  .blog-card-desc {
    font-size: 15px;
    color: var(--text-secondary);
    line-height: 1.6;
    flex: 1;
    margin-bottom: 20px;
  }
  .blog-card-meta {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    color: var(--text-muted);
  }
  .blog-card-dot {
    width: 3px;
    height: 3px;
    border-radius: 50%;
    background: var(--text-muted);
  }
  @media (max-width: 768px) {
    .blog-hero { padding: 48px 0 32px; }
    .blog-hero-title { font-size: 36px; }
    .blog-hero-desc { font-size: 16px; }
    .blog-grid { grid-template-columns: 1fr; gap: 16px; }
    .blog-card { padding: 24px; }
    .blog-card-title { font-size: 19px; }
  }
`;
