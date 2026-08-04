# CineBar Website

The public product website for CineBar, a macOS menu-bar discovery tool for
movies and television. It runs on
[vinext](https://github.com/cloudflare/vinext), with optional Cloudflare D1 and
Drizzle support inherited from the Sites project shape.

## Prerequisites

- Node.js `>=22.13.0`

## Quick Start

```bash
npm install
npm run dev
npm run build
```

This starter does not use `wrangler.jsonc` for local development.

## Included Shape

- edit site code under `app/`
- `.openai/hosting.json` declares optional Sites D1 and R2 bindings
- `vite.config.ts` simulates declared bindings for local development
- `db/schema.ts` starts intentionally empty
- `examples/d1/` contains an optional D1 example surface
- `drizzle.config.ts` supports local migration generation when needed

## 账号与隐私

CineBar 官网是公开页面，不要求 GPT、ChatGPT 或其他账号登录。片单、偏好和
应用内功能仍由 CineBar 客户端在本机管理；只有匿名安装统计后台使用独立的管理员
凭据，不通过网页登录。

## Useful Commands

- `npm run dev`: start local development
- `npm run build`: verify the vinext build output
- `npm test`: build the CineBar site and verify the required product content,
  navigation sections, appearance preferences, and tracked Sites Vite plugin
- `npm run db:generate`: generate Drizzle migrations after schema changes

## Learn More

- [vinext Documentation](https://github.com/cloudflare/vinext)
- [Drizzle D1 Guide](https://orm.drizzle.team/docs/get-started/d1-new)
