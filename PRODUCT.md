# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary: developers learning real-time graphics who follow a project post by post (CUDA, OpenGL, ray tracing, a D3D12/Vulkan renderer). They come in from search or a link, usually to one post, and the goal is for them to read a whole series and run the code from its linked repo.

Secondary: industry peers and recruiters judging the author's depth. The About page frames the author as roughly 20 years in real-time graphics, games, military simulation and VFX, now an engineering leader at Qualcomm Snapdragon Game Studio who stays hands-on with personal rendering projects. Learners come first; portfolio value follows from the quality of the teaching.

## Product Purpose

The Pixel Dump is a personal Hugo blog and project index. Long-running rendering projects are documented post by post, each with a repo, diagrams and screenshots. Success is a visitor finishing a series, not skimming one page.

## Positioning

Each series is a working renderer built in public, with every post tied to a real diff in a real repo. The posts explain in plain words and diagrams instead of formula-first maths.

## Operating Context

- Series on the site today: CUDA Ray Tracer, Multithreaded Ray Tracer, OpenGL Step by Step and Janus (a from-scratch renderer with D3D12 and Vulkan back ends, one post so far).
- Posts are written from a diff in the author's source repos, then reviewed by the author before publishing. Series are ordered; the project pages list posts in reading order and the blog index shows newest first.
- Content is Markdown in `content/`, with SVG diagrams in `static/images/blog/`.

## Capabilities and Constraints

- Static Hugo site (theme `enervoid-theme`, Tailwind via browser CDN, swup page transitions, KaTeX, Mermaid), hosted on GitHub Pages. No server code.
- Dark theme only. There is no light mode and none is planned.
- Posts use plain-word maths, with graphs preferred over formulas, and no em dashes.
- Each series shows a disclaimer that Claude helped write it, linked to that series' own repo. It is part of the product and must not be dropped by design changes.
- SVG diagrams are inlined at build time and styled by the page's fonts.

## Brand Commitments

Site name "The Pixel Dump". Tone is plain, technically confident, lightly self-deprecating (see the About page). Typefaces confirmed by the author: Space Grotesk for headings and numbers, Inter for body text, SUSE Mono for code.

## Evidence on Hand

- About copy: `content/about.md`. Resume: `content/personal/resume.md`.
- About 46 SVG diagrams and per-project cover images (some taken from demo videos) under `static/images/`.
- Four series and 59 posts (CUDA 11, Multithreaded Raytracer 17, OpenGL 30, Janus 1), each series with a linked GitHub repo.
- There are no testimonials, analytics or traffic figures on hand. Do not invent any.

## Product Principles

1. Serve the person reading a series end to end: order, progress and the link to the next post matter more than the front page.
2. Explain before formulas: graphs and everyday words come first, and the code is shown beside the explanation.
3. Every diagram and code block is part of the lesson, so it must stay legible at phone width and copyable.
4. Be honest about authorship: the disclaimer stays visible and the repos stay linked.
5. Keep the site static and cheap to host so a post can ship as a Markdown file.

## Accessibility & Inclusion

Body text and muted text target WCAG AA contrast (4.5:1) on the dark background. Keyboard focus must be visible. Motion respects `prefers-reduced-motion`. Diagrams carry text alternatives.
