import type { MetaFunction, LoaderFunctionArgs } from "react-router";
import { Link, useLoaderData } from "react-router";
import { blogPosts, getBlogPost } from "~/data/blog-posts";

export function loader({ params }: LoaderFunctionArgs) {
  const post = getBlogPost(params.slug!);
  if (!post) {
    throw new Response("Not Found", { status: 404 });
  }
  return { post };
}

export const meta: MetaFunction<typeof loader> = ({ data }) => {
  if (!data?.post) return [{ title: "Not Found - MacPlayer" }];
  const { post } = data;
  return [
    { title: `${post.title} - MacPlayer Blog` },
    { name: "description", content: post.description },
    { property: "og:type", content: "article" },
    { property: "og:title", content: post.title },
    { property: "og:description", content: post.description },
    { property: "article:published_time", content: post.date },
    { name: "twitter:card", content: "summary_large_image" },
    { name: "twitter:title", content: post.title },
    { name: "twitter:description", content: post.description },
    { name: "robots", content: "index, follow" },
  ];
};

function renderMarkdown(content: string) {
  const lines = content.trim().split("\n");
  const elements: React.ReactNode[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    // Headings
    if (line.startsWith("### ")) {
      elements.push(<h3 key={i}>{processInline(line.slice(4))}</h3>);
      i++;
      continue;
    }
    if (line.startsWith("## ")) {
      elements.push(<h2 key={i}>{processInline(line.slice(3))}</h2>);
      i++;
      continue;
    }

    // Code block
    if (line.startsWith("```")) {
      const codeLines: string[] = [];
      i++;
      while (i < lines.length && !lines[i].startsWith("```")) {
        codeLines.push(lines[i]);
        i++;
      }
      elements.push(
        <pre key={`code-${i}`} className="blog-code"><code>{codeLines.join("\n")}</code></pre>
      );
      i++;
      continue;
    }

    // Table
    if (line.includes("|") && line.trim().startsWith("|")) {
      const tableRows: string[][] = [];
      while (i < lines.length && lines[i].includes("|") && lines[i].trim().startsWith("|")) {
        const cells = lines[i].split("|").slice(1, -1).map((c) => c.trim());
        tableRows.push(cells);
        i++;
      }
      // Skip separator row (|---|---|)
      const headerRow = tableRows[0];
      const bodyRows = tableRows.filter((_, idx) => idx >= 2);
      elements.push(
        <div key={`table-${i}`} className="blog-table-wrap">
          <table className="blog-table">
            <thead>
              <tr>{headerRow.map((cell, ci) => <th key={ci}>{processInline(cell)}</th>)}</tr>
            </thead>
            <tbody>
              {bodyRows.map((row, ri) => (
                <tr key={ri}>{row.map((cell, ci) => <td key={ci}>{processInline(cell)}</td>)}</tr>
              ))}
            </tbody>
          </table>
        </div>
      );
      continue;
    }

    // Unordered list
    if (line.startsWith("- ")) {
      const items: React.ReactNode[] = [];
      while (i < lines.length && lines[i].startsWith("- ")) {
        items.push(<li key={i}>{processInline(lines[i].slice(2))}</li>);
        i++;
      }
      elements.push(<ul key={`ul-${i}`}>{items}</ul>);
      continue;
    }

    // Ordered list
    if (/^\d+\.\s/.test(line)) {
      const items: React.ReactNode[] = [];
      while (i < lines.length && /^\d+\.\s/.test(lines[i])) {
        items.push(<li key={i}>{processInline(lines[i].replace(/^\d+\.\s/, ""))}</li>);
        i++;
      }
      elements.push(<ol key={`ol-${i}`}>{items}</ol>);
      continue;
    }

    // Empty line
    if (line.trim() === "") {
      i++;
      continue;
    }

    // Paragraph — collect consecutive non-empty, non-special lines
    const paraLines: string[] = [];
    while (
      i < lines.length &&
      lines[i].trim() !== "" &&
      !lines[i].startsWith("#") &&
      !lines[i].startsWith("```") &&
      !lines[i].startsWith("- ") &&
      !/^\d+\.\s/.test(lines[i]) &&
      !(lines[i].includes("|") && lines[i].trim().startsWith("|"))
    ) {
      paraLines.push(lines[i]);
      i++;
    }
    if (paraLines.length > 0) {
      elements.push(<p key={`p-${i}`}>{processInline(paraLines.join(" "))}</p>);
    }
  }

  return elements;
}

function processInline(text: string): React.ReactNode {
  const parts: React.ReactNode[] = [];
  // Match **bold**, `code`, and plain text
  const regex = /(\*\*(.+?)\*\*|`([^`]+?)`)/g;
  let lastIndex = 0;
  let match;
  let keyCounter = 0;

  while ((match = regex.exec(text)) !== null) {
    if (match.index > lastIndex) {
      parts.push(text.slice(lastIndex, match.index));
    }
    if (match[2]) {
      parts.push(<strong key={keyCounter++}>{match[2]}</strong>);
    } else if (match[3]) {
      parts.push(<code key={keyCounter++} className="blog-inline-code">{match[3]}</code>);
    }
    lastIndex = regex.lastIndex;
  }
  if (lastIndex < text.length) {
    parts.push(text.slice(lastIndex));
  }
  return parts.length === 1 ? parts[0] : parts;
}

export default function BlogPost() {
  const { post } = useLoaderData<typeof loader>();

  // Find adjacent posts for navigation
  const currentIndex = blogPosts.findIndex((p) => p.slug === post.slug);
  const prevPost = currentIndex < blogPosts.length - 1 ? blogPosts[currentIndex + 1] : null;
  const nextPost = currentIndex > 0 ? blogPosts[currentIndex - 1] : null;

  return (
    <>
      <article className="blog-post">
        <div className="container blog-container">
          <Link to="/blog" className="blog-back">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
              <path d="M10 3L5 8L10 13" />
            </svg>
            All posts
          </Link>

          <header className="blog-post-header">
            <div className="blog-post-tag">{post.tag}</div>
            <h1 className="blog-post-title">{post.title}</h1>
            <div className="blog-post-meta">
              <time>{post.date}</time>
              <span className="blog-post-dot" />
              <span>{post.readTime} read</span>
            </div>
          </header>

          <div className="blog-post-body">
            {renderMarkdown(post.content)}
          </div>

          <nav className="blog-post-nav">
            {prevPost ? (
              <Link to={`/blog/${prevPost.slug}`} className="blog-nav-link blog-nav-prev">
                <span className="blog-nav-label">Previous</span>
                <span className="blog-nav-title">{prevPost.title}</span>
              </Link>
            ) : <div />}
            {nextPost ? (
              <Link to={`/blog/${nextPost.slug}`} className="blog-nav-link blog-nav-next">
                <span className="blog-nav-label">Next</span>
                <span className="blog-nav-title">{nextPost.title}</span>
              </Link>
            ) : <div />}
          </nav>
        </div>
      </article>

      <style>{blogPostStyles}</style>
    </>
  );
}

const blogPostStyles = `
  .blog-post { padding: 48px 0 120px; }
  .blog-container { max-width: 760px; }
  .blog-back {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 14px;
    color: var(--text-secondary);
    margin-bottom: 40px;
    transition: color 0.2s;
  }
  .blog-back:hover { color: var(--text); }

  .blog-post-header { margin-bottom: 48px; }
  .blog-post-tag {
    display: inline-block;
    padding: 4px 12px;
    font-size: 12px;
    font-weight: 500;
    color: var(--primary);
    background: var(--primary-glow);
    border-radius: 20px;
    margin-bottom: 20px;
  }
  .blog-post-title {
    font-size: 42px;
    font-weight: 700;
    letter-spacing: -0.03em;
    line-height: 1.15;
    margin-bottom: 16px;
  }
  .blog-post-meta {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 14px;
    color: var(--text-muted);
  }
  .blog-post-dot {
    width: 3px;
    height: 3px;
    border-radius: 50%;
    background: var(--text-muted);
  }

  .blog-post-body {
    font-size: 17px;
    line-height: 1.8;
    color: rgba(255, 255, 255, 0.85);
  }
  .blog-post-body h2 {
    font-size: 28px;
    font-weight: 600;
    letter-spacing: -0.02em;
    color: var(--text);
    margin: 48px 0 16px;
  }
  .blog-post-body h3 {
    font-size: 22px;
    font-weight: 600;
    color: var(--text);
    margin: 36px 0 12px;
  }
  .blog-post-body p {
    margin-bottom: 20px;
  }
  .blog-post-body ul, .blog-post-body ol {
    margin: 0 0 20px 24px;
  }
  .blog-post-body li {
    margin-bottom: 8px;
  }
  .blog-post-body strong {
    color: var(--text);
    font-weight: 600;
  }
  .blog-inline-code {
    padding: 2px 7px;
    font-size: 0.9em;
    background: rgba(255, 255, 255, 0.08);
    border-radius: 5px;
    font-family: 'SF Mono', 'Fira Code', monospace;
  }
  .blog-table-wrap {
    margin: 20px 0;
    overflow-x: auto;
    border-radius: 12px;
    border: 1px solid var(--border);
  }
  .blog-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 15px;
  }
  .blog-table th {
    padding: 12px 16px;
    text-align: left;
    font-weight: 600;
    color: var(--text);
    background: rgba(255, 255, 255, 0.04);
    border-bottom: 1px solid var(--border);
  }
  .blog-table td {
    padding: 10px 16px;
    color: rgba(255, 255, 255, 0.8);
    border-bottom: 1px solid rgba(255, 255, 255, 0.04);
  }
  .blog-table tr:last-child td { border-bottom: none; }
  .blog-table tr:hover td { background: rgba(255, 255, 255, 0.02); }
  .blog-code {
    display: block;
    padding: 20px 24px;
    margin: 20px 0;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--border);
    border-radius: 12px;
    overflow-x: auto;
    font-size: 14px;
    line-height: 1.6;
    font-family: 'SF Mono', 'Fira Code', monospace;
    color: rgba(255, 255, 255, 0.8);
  }

  .blog-post-nav {
    display: flex;
    justify-content: space-between;
    gap: 20px;
    margin-top: 64px;
    padding-top: 32px;
    border-top: 1px solid var(--border);
  }
  .blog-nav-link {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 16px 20px;
    border: 1px solid var(--border);
    border-radius: 12px;
    text-decoration: none;
    transition: all 0.2s;
    max-width: 48%;
  }
  .blog-nav-link:hover {
    border-color: var(--border-hover);
    background: var(--bg-card);
  }
  .blog-nav-next { text-align: right; margin-left: auto; }
  .blog-nav-label {
    font-size: 12px;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .blog-nav-title {
    font-size: 15px;
    font-weight: 500;
    color: var(--text);
    line-height: 1.4;
  }

  @media (max-width: 768px) {
    .blog-post { padding: 32px 0 80px; }
    .blog-post-title { font-size: 30px; }
    .blog-post-body { font-size: 16px; }
    .blog-post-body h2 { font-size: 24px; margin-top: 36px; }
    .blog-post-body h3 { font-size: 20px; }
    .blog-post-nav { flex-direction: column; }
    .blog-nav-link { max-width: 100%; }
    .blog-nav-next { text-align: left; }
  }
`;
